-- {"query": "54042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1333} 

-- Example of a high‑complexity benchmark query on the StackOverflow schema

WITH
  /* 1. Count posts per user                                    */
  UserPosts AS (
    SELECT
      p.OwnerUserId    AS UserId,
      COUNT(*)         AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
      SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END) AS Wikis
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
  ),

  /* 2. Aggregate votes on each post (by type)                   */
  PostVotes AS (
    SELECT
      v.PostId,
      v.VoteTypeId,
      COUNT(*) AS VoteCount
    FROM Votes v
    GROUP BY v.PostId, v.VoteTypeId
  ),

  /* 3. Compute per‑post vote totals (up/down) and acceptance   */
  PostScore AS (
    SELECT
      p.Id,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                        WHEN v.VoteTypeId = 3 THEN -1
                        ELSE 0 END), 0)          AS NetScore,
      MAX(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS Accepted,
      p.OwnerUserId,
      p.PostTypeId,
      p.Tags,
      p.AverageScore         AS AvgScore,   -- placeholder for any built‑in column
      p.LastActivityDate
    FROM Posts p
    LEFT JOIN PostVotes v
      ON v.PostId = p.Id AND v.VoteTypeId IN (1,2,3)
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Tags, p.LastActivityDate
  ),

  /* 4. Aggregate tag usage per user                              */
  UserTagUsage AS (
    SELECT
      u.Id                               AS UserId,
      SUM(CASE
            WHEN p.Tags IS NOT NULL AND p.PostTypeId = 1
            THEN array_length(string_to_array(p.Tags,'>'),1)
            ELSE 0
          END)                           AS TagCount,
      COUNT(DISTINCT
        UNNEST(
          SELECT regexp_replace(tag, '^<|>$', '', 'g')
          FROM unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
        )
      ) AS UniqueTagsUsed
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    GROUP BY u.Id
  ),

  /* 5. Compute comment activity per user                          */
  UserComments AS (
    SELECT
      c.UserId,
      COUNT(*)            AS TotalComments,
      SUM(CASE WHEN c.Score > 0 THEN c.Score ELSE 0 END) AS PositiveScore,
      SUM(CASE WHEN c.Score < 0 THEN -c.Score ELSE 0 END) AS NegativeScore
    FROM Comments c
    GROUP BY c.UserId
  ),

  /* 6. Calculate a composite engagement score per user           */
  Engagement AS (
    SELECT
      u.Id                  AS UserId,
      u.Reputation,
      COALESCE(ups.TotalPosts,0)    AS TotalPosts,
      COALESCE(ups.Questions,0)     AS Questions,
      COALESCE(ups.Answers,0)       AS Answers,
      COALESCE(uds.TagCount,0)      AS TagCount,
      COALESCE(uds.UniqueTagsUsed,0) AS UniqueTagsUsed,
      COALESCE(uc.TotalComments,0)  AS TotalComments,
      COALESCE(uc.PositiveScore,0)  AS PositiveCommentScore,
      COALESCE(uc.NegativeScore,0)  AS NegativeCommentScore,
      COALESCE(SUM(ps.NetScore),0)  AS TotalVoteScore,
      COALESCE(SUM(ps.Accepted),0)  AS AcceptedAnswers,
      COUNT(d.Id)            AS PostHistoryActions
    FROM Users u
    LEFT JOIN UserPosts ups ON ups.UserId = u.Id
    LEFT JOIN UserTagUsage uds ON uds.UserId = u.Id
    LEFT JOIN UserComments uc ON uc.UserId = u.Id
    LEFT JOIN PostScore ps ON ps.OwnerUserId = u.Id
    LEFT JOIN PostHistory d ON d.UserId = u.Id
    GROUP BY u.Id, u.Reputation, ups.TotalPosts, ups.Questions, ups.Answers,
             uds.TagCount, uds.UniqueTagsUsed,
             uc.TotalComments, uc.PositiveScore, uc.NegativeScore
  )

SELECT
  e.UserId,
  u.DisplayName,
  e.Reputation,
  e.TotalPosts,
  e.Questions,
  e.Answers,
  e.TagCount,
  e.UniqueTagsUsed,
  e.TotalComments,
  e.PositiveCommentScore,
  e.NegativeCommentScore,
  e.TotalVoteScore,
  e.AcceptedAnswers,
  e.PostHistoryActions,
  /* Normalized engagement metric across all users      */
  ROUND(100.0 * (e.TotalPosts + e.Questions + e.Answers + 
                 e.TagCount + e.UniqueTagsUsed + 
                 e.TotalComments + e.PositiveCommentScore - 
                 e.NegativeCommentScore + e.TotalVoteScore + 
                 e.AcceptedAnswers), 2) AS EngagementScore
FROM Engagement e
JOIN Users u ON u.Id = e.UserId
ORDER BY EngagementScore DESC
LIMIT 100;
