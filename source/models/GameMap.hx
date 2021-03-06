package models;

import constants.Constants.MapGenerationConsts;
import flixel.math.FlxRandom;
import flixel.util.FlxSave;
import haxe.Exception;
import models.events.*;
import utils.GameUtils;

typedef Column = Array<Node>;

// a node in the map
class Node
{
	public var id:Int;
	public var connectedNodesId:Array<Int> = new Array<Int>();
	public var event:GameEvent;

	public function new(id:Int, ?event:GameEvent)
	{
		this.id = id;
		this.event = event;
	}
}

// the game map. The GameMapView will then take the nodes and
// render it on the screen.
class GameMap
{
	public var columns:Array<Column>;

	// reference to the global RNG
	var random:FlxRandom;

	public function print()
	{
		for (i in 0...columns.length)
		{
			var traceVal:String = '';
			var column = columns[i];
			for (i in 0...column.length)
			{
				traceVal += 'id:${column[i].id} name:${column[i].event.name}, ';
			}
			trace(traceVal);
		}
	}

	function numNodesWeightedPick()
	{
		var items = MapGenerationConsts.NUM_NODE_CHANCE_ITEMS;
		var weights = MapGenerationConsts.NUM_NODE_CHANCE_WEIGHTS;
		return GameUtils.weightedPick(items, weights);
	}

	function nodeTypeWeightedPick()
	{
		var items = MapGenerationConsts.NODE_TYPE_CHANCE_ITEMS;
		var weights = MapGenerationConsts.NODE_TYPE_CHANCE_WEIGHTS;
		return GameUtils.weightedPick(items, weights);
	}

	function createEventPool(length:Int)
	{
		var eventPool = new Array<GameEvent>();
		var counter = 0;
		// add the guaranteed events in first
		for (i in 0...MapGenerationConsts.MIN_BATTLES)
		{
			eventPool.push(BattleEvent.sampleBattle());
			counter++;
		}
		for (i in 0...MapGenerationConsts.MIN_CHOICES)
		{
			eventPool.push(ChoiceEvent.sample());
			counter++;
		}

		// now add the variable events to the pool, based on their weight;
		while (counter < length)
		{
			var event:GameEvent;
			var type = nodeTypeWeightedPick();
			switch (type)
			{
				case 'BATTLE':
					event = BattleEvent.sampleBattle();
				case 'TREASURE':
					event = TreasureEvent.sample();
				case 'CHOICE':
					event = ChoiceEvent.sample();
				case 'REST':
					event = RestEvent.sample();
				default:
					event = new NoneEvent();
			}
			eventPool.push(event);
			counter++;
		}
		if (eventPool.length != length)
		{
			throw new Exception('bad eventPool length ${eventPool.length}');
		}
		return eventPool;
	}

	function fillVariableNodes(variableNodes:Array<Node>)
	{
		// add a treasure somewhere in the first half.
		var nodeInd = random.int(0, Math.round(variableNodes.length / 2) - 1);
		variableNodes[nodeInd].event = TreasureEvent.sample();
		variableNodes.splice(nodeInd, 1);
		// add a treasure somewhere in the second half.
		nodeInd = random.int(Math.round(variableNodes.length / 2), variableNodes.length - 1);
		variableNodes[nodeInd].event = TreasureEvent.sample();
		variableNodes.splice(nodeInd, 1);
		// add 2 elites to the second half.
		nodeInd = random.int(Math.round(variableNodes.length / 2), variableNodes.length - 1);
		variableNodes[nodeInd].event = BattleEvent.sampleElite();
		variableNodes.splice(nodeInd, 1);

		nodeInd = random.int(Math.round(variableNodes.length / 2), variableNodes.length - 1);
		variableNodes[nodeInd].event = BattleEvent.sampleElite();
		variableNodes.splice(nodeInd, 1);

		// now, create a pool of events to be assigned to the rest nodes
		var eventPool = createEventPool(variableNodes.length);

		// for each of these nodes, assign an event to it and remove the event from the pool
		for (i in 0...variableNodes.length)
		{
			var eventInd = random.int(0, eventPool.length - 1);
			variableNodes[i].event = eventPool[eventInd];
			eventPool.splice(eventInd, 1);
		}
		if (eventPool.length != 0)
		{
			throw new Exception('event pool not empty after assignment: ${eventPool.length}');
		}
	}

	function connectNodes()
	{
		for (i in 0...columns.length - 1)
		{
			var column = columns[i];
			var nextColumn = columns[i + 1];
			var highestConnectedNode = 0; // index of that node in the next column
			for (j in 0...column.length)
			{
				var node = column[j];
				var connectToHighestConnected:Bool;
				// you must connect to the previously highest connected node if you are the first node in your column,
				// or if the highest connected node is the last node in the next column
				if (j == 0 || highestConnectedNode == nextColumn.length - 1)
					connectToHighestConnected = true;
				else
					connectToHighestConnected = random.bool();

				// the first connected node is either the highest connected node from the previous node in this column
				// or the next one after the highest connected node.
				var connectedStart:Int;
				if (connectToHighestConnected)
					connectedStart = highestConnectedNode;
				else
					connectedStart = highestConnectedNode + 1;

				// if you are the last node, your connectEnd must be the end of the next column
				// else, it can be anywhere from your connectedStart to the end of the next column
				var connectedEnd:Int;
				if (j == column.length - 1)
					connectedEnd = nextColumn.length - 1;
				else
					connectedEnd = random.int(connectedStart, nextColumn.length - 1);

				if (connectedEnd > nextColumn.length - 1)
					throw new Exception('connected end past end of next column');

				for (idx in connectedStart...connectedEnd + 1)
				{
					node.connectedNodesId.push(nextColumn[idx].id);
				}
				highestConnectedNode = connectedEnd;
			}
		}
	}

	public function new(numColumns:Int = 18)
	{
		this.random = GameUtils.rng;

		trace('generated map with seed ${random.currentSeed}');
		GameUtils.save.data.seed = random.currentSeed;

		// nodes that are empty until the end. We will fill them with an event after we
		// fill in the pre determined nodes (e.g. the starting home node)
		var variableNodes = new Array<Node>();
		var idCounter = 0;

		this.columns = new Array<Column>();
		for (i in 0...numColumns)
		{
			var column = new Column();

			// create the initial "home" node in first column
			if (i == 0)
			{
				var node = new Node(0, new HomeEvent('Home'));
				column.push(node);
			}
			// create the boss node in the last column
			else if (i == numColumns - 1)
			{
				var node = new Node(++idCounter, BattleEvent.sampleBoss());
				column.push(node);
			}
			// for all the nodes in between, create empty ones to be filled in later.
			else
			{
				var nodesInColumn = numNodesWeightedPick();

				for (j in 0...nodesInColumn)
				{
					var node = new Node(++idCounter);
					// if we're at the halfway point, make them rest nodes.
					if (i == Math.round(numColumns / 2))
					{
						node.event = RestEvent.sample();
					}
					else
					{
						variableNodes.push(node);
					}
					column.push(node);
				}
			}

			// finally, add this column to the map
			this.columns.push(column);
		}
		fillVariableNodes(variableNodes);
		connectNodes();
	}
}
