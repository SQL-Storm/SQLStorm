-- {"query": "44083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1002}

WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Posts ap
        WHERE ap.ParentId = p.Id
        AND ap.PostTypeId = 2
        AND ap.Score >= 0
      )
      ELSE 0
    END AS AnswersCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 2
      )
      ELSE 0
    END AS UpVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 3
      )
      ELSE 0
    END AS DownVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 5
      )
      ELSE 0
    END AS FavoriteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId IN (6, 7)
      )
      ELSE 0
    END AS CloseVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (10, 11)
      )
      ELSE 0
    END AS CloseReopenCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
        AND b.Name IN ('Accepted', 'Enlightened', 'Populist', 'Socratic')
      )
      ELSE 0
    END AS OwnerBadgeCount
  FROM Posts p
)
SELECT
  PostId,
  PostTypeId,
  OwnerUserId,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  AnswersCount,
  UpVotes,
  DownVotes,
  FavoriteCount,
  CloseVotes,
  CloseReopenCount,
  OwnerBadgeCount
FROM cte
WHERE PostTypeId = 1
ORDER BY LastActivityDate DESC
LIMIT 100;
```

This query retrieves the top 100 most recently active questions from the StackOverflow database, along with various metrics related to each question, such as the number of answers, upvotes, downvotes, favorite count, close votes, close/reopen count, and the number of badges earned by the question owner.

The key aspects of this query are:

1. The use of a common table expression (CTE) to encapsulate the complex logic for calculating the various metrics for each question.
2. The extensive use of conditional logic (CASE statements) to handle the differences between question and answer posts, as well as the various vote types and post history events.
3. The final SELECT statement that filters the results to only include question posts (PostTypeId = 1) and orders the results by the LastActivityDate in descending order to get the most recently active questions.

This query can be used as a starting point for performance benchmarking, as it exercises a variety of database operations and accesses multiple tables to retrieve the desired information.
