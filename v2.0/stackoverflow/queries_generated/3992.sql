-- {"query": "3992.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1741} 

/*  Benchmark Query:  Complex analytics over StackOverflow schema */
WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        NULL::int      AS ParentTagId,
        1              AS Depth,
        t.Count        AS TagUsage
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        ct.Id,
        ct.TagName,
        th.Id          AS ParentTagId,
        th.Depth + 1   AS Depth,
        ct.Count       AS TagUsage
    FROM Tags ct
    JOIN tag_hierarchy th ON ct.TagName LIKE th.TagName || '-%'
    WHERE ct.IsModeratorOnly = 0
),
user_activity AS (
    SELECT 
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0)      AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0)      AS DownVotesGiven,
        COALESCE(COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1),0)            AS QuestionsAsked,
        COALESCE(COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2),0)            AS AnswersGiven,
        MAX(u.LastAccessDate)                                            AS LastSeen,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                  AS RepRank
    FROM Users u
    LEFT JOIN Votes v          ON v.UserId = u.Id
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_summary AS (
    SELECT 
        b.UserId,
        COUNT(*)                                    AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1)         AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)         AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)         AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ')           AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
post_score_stats AS (
    SELECT 
        p.OwnerUserId                               AS UserId,
        AVG(p.Score)                                AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        MAX(p.Score)                                AS MaxPostScore,
        MIN(p.Score)                                AS MinPostScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId)  AS TotalPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)                     -- questions and answers only
    GROUP BY p.OwnerUserId
),
recent_closed_questions AS (
    SELECT 
        q.Id                                        AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.ClosedDate,
        ph.Comment                                  AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.ClosedDate DESC) AS rn
    FROM Posts q
    JOIN PostHistory ph 
        ON ph.PostId = q.Id 
       AND ph.PostHistoryTypeId = 10                -- Close event
    WHERE q.PostTypeId = 1 
      AND q.ClosedDate IS NOT NULL
),
tagged_posts AS (
    SELECT 
        p.Id                                        AS PostId,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_popularity AS (
    SELECT 
        tp.TagName,
        COUNT(*)                                     AS PostsWithTag,
        SUM(p.Score)                                 AS TotalScore,
        AVG(p.Score)                                 AS AvgScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)  AS TagRank
    FROM tagged_posts tp
    JOIN Posts p ON p.Id = tp.PostId
    GROUP BY tp.TagName
),
final_report AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.RepRank,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.BadgeList,
        ps.AvgPostScore,
        ps.MedianPostScore,
        ps.MaxPostScore,
        ps.MinPostScore,
        ps.TotalPosts,
        rcq.QuestionId,
        rcq.Title               AS ClosedQuestionTitle,
        rcq.CloseReason,
        rcq.ClosedDate,
        COALESCE(tp.TagRank, 0) AS TopTagRank,
        COALESCE(tp.TagName, 'N/A') AS TopTagName,
        COALESCE(tp.PostsWithTag, 0) AS PostsWithTopTag,
        CASE 
            WHEN ua.Reputation > 100000 THEN 'Legendary'
            WHEN ua.Reputation > 50000  THEN 'Epic'
            WHEN ua.Reputation > 20000  THEN 'Veteran'
            ELSE 'Member'
        END AS ReputationTier,
        -- Detect users with suspiciously high upvote ratio
        CASE 
            WHEN ua.UpVotesGiven + ua.DownVotesGiven = 0 THEN NULL
            WHEN ua.UpVotesGiven::float / (ua.UpVotesGiven + ua.DownVotesGiven) > 0.95 THEN TRUE
            ELSE FALSE
        END AS HighUpvoteRatio,
        -- Null‑aware comparison: has user ever posted a question without tags?
        EXISTS (
            SELECT 1 
            FROM Posts p 
            WHERE p.OwnerUserId = ua.UserId 
              AND p.PostTypeId = 1 
              AND (p.Tags IS NULL OR TRIM(p.Tags) = '')
        ) AS HasUntaggedQuestions
    FROM user_activity ua
    LEFT JOIN badge_summary bs      ON bs.UserId = ua.UserId
    LEFT JOIN post_score_stats ps   ON ps.UserId = ua.UserId
    LEFT JOIN recent_closed_questions rcq 
           ON rcq.OwnerUserId = ua.UserId AND rcq.rn = 1
    LEFT JOIN LATERAL (
        SELECT 
            tp.TagName,
            tp.TagRank,
            tp.PostsWithTag
        FROM tag_popularity tp
        ORDER BY tp.TagRank
        LIMIT 1
    ) tp ON TRUE
)
SELECT *
FROM final_report
WHERE ReputationTier IN ('Veteran','Epic','Legendary')
   OR HighUpvoteRatio = TRUE
   OR HasUntaggedQuestions = TRUE
ORDER BY RepRank
LIMIT 100
UNION ALL
SELECT 
    NULL AS UserId,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS RepRank,
    NULL AS TotalBadges,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS BadgeList,
    NULL AS AvgPostScore,
    NULL AS MedianPostScore,
    NULL AS MaxPostScore,
    NULL AS MinPostScore,
    NULL AS TotalPosts,
    NULL AS QuestionId,
    NULL AS ClosedQuestionTitle,
    NULL AS CloseReason,
    NULL AS ClosedDate,
    NULL AS TopTagRank,
    NULL AS TopTagName,
    NULL AS PostsWithTopTag,
    NULL AS ReputationTier,
    NULL AS HighUpvoteRatio,
    NULL AS HasUntaggedQuestions
FROM (SELECT 1) dummy
ORDER BY RepRank NULLS LAST;
