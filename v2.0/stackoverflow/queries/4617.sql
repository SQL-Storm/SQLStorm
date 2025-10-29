-- {"query": "4617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 966}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  RecentEditors AS (
    SELECT
      rpe.PostId,
      u.DisplayName AS EditorDisplayName,
      p.Title AS PostTitle,
      pt.Name AS PostTypeName,
      CASE
        WHEN rpe.PostHistoryTypeId = 4 THEN 'Title Edited'
        WHEN rpe.PostHistoryTypeId = 5 THEN 'Body Edited'
        WHEN rpe.PostHistoryTypeId = 6 THEN 'Tags Edited'
      END AS EditType
    FROM
      RankedPostEdits rpe
      JOIN Users u
        ON rpe.UserId = u.Id
      JOIN Posts p
        ON rpe.PostId = p.Id
      JOIN PostTypes pt
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
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
      LEFT JOIN Comments c
        ON u.Id = c.UserId
      LEFT JOIN Votes v
        ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagWisePostCounts AS (
    SELECT
      TRIM(tag) AS TagName,
      COUNT(*) AS PostCount
    FROM (
      SELECT
        p.Id,
        p.Tags
      FROM
        Posts p
      WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
    ) posts_with_tags,
    LATERAL (
      WITH RECURSIVE splitter(tag, rest) AS (
        SELECT
          CASE
            WHEN position('><' IN substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2)) = 0
            THEN substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2)
            ELSE substring(substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2) FROM 1 FOR position('><' IN substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2)) - 1)
          END,
          CASE
            WHEN position('><' IN substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2)) = 0
            THEN ''
            ELSE substring(substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2) FROM position('><' IN substring(posts_with_tags.Tags FROM 2 FOR char_length(posts_with_tags.Tags) - 2)) + 2)
          END
        UNION ALL
        SELECT
          CASE
            WHEN position('><' IN rest) = 0 THEN rest
            ELSE substring(rest FROM 1 FOR position('><' IN rest) - 1)
          END,
          CASE
            WHEN position('><' IN rest) = 0 THEN ''
            ELSE substring(rest FROM position('><' IN rest) + 2)
          END
        FROM splitter
        WHERE rest <> ''
      )
      SELECT tag FROM splitter WHERE tag IS NOT NULL
    ) split_tags
    GROUP BY
      TRIM(tag)
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
  RecentEditors RE
FULL OUTER JOIN HighReputationUsers H
  ON RE.PostId = H.Id
LEFT JOIN UserActivity UA
  ON UA.UserId = H.Id
LEFT JOIN TagWisePostCounts T
  ON T.TagName = RE.PostTitle
WHERE
  (UA.PostsCreated > 100 OR UA.PostsCreated IS NULL)
  OR (UA.CommentsMade < 50 OR UA.CommentsMade IS NULL)
  OR ( (COALESCE(UA.UpVotesGiven,0) - COALESCE(UA.DownVotesGiven,0)) > 500 )
  OR T.TagName IN ('sql', 'performance', 'query', 'optimization')
GROUP BY
  RE.EditorDisplayName,
  RE.PostTitle,
  RE.PostTypeName,
  RE.EditType,
  H.DisplayName,
  H.Reputation,
  UA.PostsCreated,
  UA.CommentsMade,
  UA.UpVotesGiven,
  UA.DownVotesGiven,
  T.TagName,
  T.PostCount;