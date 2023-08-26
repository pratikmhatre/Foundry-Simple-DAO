// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {TimeLock} from "../src/Timelock.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract MyGovTest is Test {
    MyGovernor myGovernor;
    TimeLock timeLock;
    GovToken govToken;
    Box box;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    address USER3 = makeAddr("user3");

    uint256 constant INITIAL_SUPPLY = 100 ether;
    uint256 constant MIN_DELAY = 3600; // 1 hr
    uint256 constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executors;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;

    function setUp() public {
        govToken = new GovToken();

        //mint tokens for the user
        govToken.mintToken(USER, INITIAL_SUPPLY);
        govToken.mintToken(USER2, INITIAL_SUPPLY);
        govToken.mintToken(USER3, INITIAL_SUPPLY);

        //re-assign the delegating power to current user
        vm.startPrank(USER);
        govToken.delegate(USER);

        //re-assign the delegating power to current user
        vm.startPrank(USER2);
        govToken.delegate(USER2);

        //re-assign the delegating power to current user
        vm.startPrank(USER3);
        govToken.delegate(USER3);

        timeLock = new TimeLock({
            minDelay: MIN_DELAY,
            proposers: proposers,
            executors: executors
        });

        myGovernor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(myGovernor)); //only governor can propose
        timeLock.grantRole(executorRole, address(0)); //anybody can execute
        timeLock.revokeRole(adminRole, USER); //USER is no longer admin
        timeLock.revokeRole(adminRole, USER2); //USER is no longer admin
        timeLock.revokeRole(adminRole, USER3); //USER is no longer admin

        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCannotUpdateBoxWithoutGovernance() external {
        vm.expectRevert();
        box.storeValue(68);
    }

    function testProposalSuccedsWithAppropriateVoting() external {
        uint256 valueToStore = 323479;
        string memory voteReason = "Becaus I love DAO's";
        bytes memory encodedCalldata = abi.encodeWithSignature(
            "storeValue(uint256)",
            valueToStore
        );

        string memory description = "Proposal to store value in box";
        targets.push(address(box));
        values.push(0);
        calldatas.push(encodedCalldata);

        //1. Propose
        uint256 proposalId = myGovernor.propose(
            targets,
            values,
            calldatas,
            description
        );
        assert(myGovernor.state(proposalId) == IGovernor.ProposalState.Pending);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        assert(myGovernor.state(proposalId) == IGovernor.ProposalState.Active);

        //2. Cast Vote
        vm.prank(USER);
        myGovernor.castVoteWithReason(proposalId, 1, voteReason);

        vm.prank(USER2);
        myGovernor.castVoteWithReason(proposalId, 0, voteReason);

        vm.prank(USER3);
        myGovernor.castVoteWithReason(proposalId, 0, voteReason);

        vm.roll(block.number + VOTING_PERIOD);
        vm.warp(block.timestamp + VOTING_PERIOD);

        //3. Queue
        myGovernor.queue(
            targets,
            values,
            calldatas,
            keccak256(abi.encodePacked(description))
        );

        assert(myGovernor.state(proposalId) == IGovernor.ProposalState.Queued);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // 4. Execute
        myGovernor.execute(
            targets,
            values,
            calldatas,
            keccak256(abi.encodePacked(description))
        );

        assert(
            myGovernor.state(proposalId) == IGovernor.ProposalState.Defeated
        );

        assert(box.getValue() == valueToStore);
    }

    function testProposalFailsIfMorePeopleVoteAgainst() external {
        uint256 valueToStore = 323479;
        string memory voteReason = "Becaus I love DAO's";
        bytes memory encodedCalldata = abi.encodeWithSignature(
            "storeValue(uint256)",
            valueToStore
        );

        string memory description = "Proposal to store value in box";
        targets.push(address(box));
        values.push(0);
        calldatas.push(encodedCalldata);

        //1. Propose
        uint256 proposalId = myGovernor.propose(
            targets,
            values,
            calldatas,
            description
        );
        assert(myGovernor.state(proposalId) == IGovernor.ProposalState.Pending);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        assert(myGovernor.state(proposalId) == IGovernor.ProposalState.Active);

        //2. Cast Vote
        vm.prank(USER);
        myGovernor.castVoteWithReason(proposalId, 1, voteReason);

        vm.prank(USER2);
        myGovernor.castVoteWithReason(proposalId, 0, voteReason);

        vm.prank(USER3);
        myGovernor.castVoteWithReason(proposalId, 0, voteReason);

        vm.roll(block.number + VOTING_PERIOD);
        vm.warp(block.timestamp + VOTING_PERIOD);

        //3. Queue
        vm.expectRevert();
        myGovernor.queue(
            targets,
            values,
            calldatas,
            keccak256(abi.encodePacked(description))
        );
    }
}
