-- {"query": "56094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 489} 

WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS PostCount
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
  SELECT t.TagName, COUNT(DISTINCT p.Id) AS PostCount
  FROM Tags t
  JOIN Posts p ON t.Id = p.Id
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY t.TagName
  HAVING COUNT(DISTINCT p.Id) > 10
),
UserTags AS (
  SELECT u.Id, t.TagName
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN PostHistory ph ON p.Id = ph.PostId
  JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  JOIN Tags t ON p.Id = t.Id
  WHERE p.PostTypeId = 1 AND p.Score > 10 AND pht.Name = 'Initial Tags'
),
TopUserTags AS (
  SELECT ut.Id, ut.TagName, COUNT(DISTINCT p.Id) AS PostCount
  FROM UserTags ut
  JOIN Posts p ON ut.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY ut.Id, ut.TagName
  HAVING COUNT(DISTINCT p.Id) > 5
)
SELECT 
  tu.Id, 
  tu.DisplayName, 
  tu.PostCount AS UserPostCount, 
  tt.TagName, 
  tt.PostCount AS TagPostCount, 
  tut.PostCount AS UserTagPostCount,
  ROW_NUMBER() OVER (ORDER BY tu.PostCount DESC) AS UserRank,
  ROW_NUMBER() OVER (ORDER BY tt.PostCount DESC) AS TagRank,
  ROW_NUMBER() OVER (PARTITION BY tut.Id ORDER BY tut.PostCount DESC) AS UserTagRank
FROM TopUsers tu
JOIN TopUserTags tut ON tu.Id = tut.Id
JOIN TopTags tt ON tut.TagName = tt.TagName
ORDER BY tu.PostCount DESC, tt.PostCount DESC, tut.PostCount DESC;
