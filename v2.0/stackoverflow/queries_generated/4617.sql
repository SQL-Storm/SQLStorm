-- {"query": "4617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 966} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  RecentEditors AS (
    SELECT
      rpe.PostId,
      u.DisplayName AS EditorDisplayName,
      p.Title AS PostTitle,
      pt.Name AS PostTypeName,
      CASE
        WHEN rpe.PostHistoryTypeId = 4
        THEN 'Title Edited'
        WHEN rpe.PostHistoryTypeId = 5
        THEN 'Body Edited'
        WHEN rpe.PostHistoryTypeId = 6
        THEN 'Tags Edited'
      END AS EditType
    FROM
      RankedPostEdits AS rpe
      JOIN Users AS u
        ON rpe.UserId = u.Id
      JOIN Posts AS p
        ON rpe.PostId = p.Id
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    WHERE
      rpe.rn = 1
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS PostsCreated,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM
      Users AS u
      LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
      LEFT JOIN Comments AS c
        ON u.Id = c.UserId
      LEFT JOIN Votes AS v
        ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagWisePostCounts AS (
    SELECT
      TRIM(Tag) AS TagName,
      COUNT(*) AS PostCount
    FROM
      Posts
      CROSS APPLY string_to_array(substring(Tags, 2, length(Tags) - 2), '><') AS Tag
    WHERE
      PostTypeId = 1 -- Questions only
      AND Tags IS NOT NULL
    GROUP BY
      TRIM(Tag)
  )
SELECT
  RE.EditorDisplayName,
  RE.PostTitle,
  RE.PostTypeName,
  RE.EditType,
  H.DisplayName AS HighRepUserDisplayName,
  H.Reputation AS HighRepUserReputation,
  UA.PostsCreated,
  UA.CommentsMade,
  UA.UpVotesGiven,
  UA.DownVotesGiven,
  T.TagName,
  T.PostCount AS TagPostCount,
  COALESCE(RE.PostTitle, 'No Title') AS CoalescedTitle,
  CASE WHEN RE.EditorDisplayName LIKE '% Moderator' THEN 'Moderator Edit' ELSE 'Regular User Edit' END AS EditorCategory
FROM
  RecentEditors AS RE
FULL OUTER JOIN HighReputationUsers AS H
  ON RE.PostId = H.Id -- Joining on PostId to check if the user who made the edit is also a high reputation user for some arbitrary reason in this benchmark query.
LEFT JOIN UserActivity AS UA
  ON UA.UserId = H.Id -- Joining UserActivity with HighReputationUsers
LEFT JOIN TagWisePostCounts AS T
  ON T.TagName = RE.PostTitle -- Joining TagWisePostCounts with RecentEditors on PostTitle for a nonsensical join condition.
WHERE
  UA.PostsCreated > 100
  OR UA.CommentsMade < 50
  OR UA.UpVotesGiven - UA.DownVotesGiven > 500
  OR T.TagName IN ('sql', 'performance', 'query', 'optimization');
