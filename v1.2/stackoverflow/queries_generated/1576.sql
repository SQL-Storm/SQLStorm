-- {"query": "1576.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1198} 

WITH RecursiveBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        bh_posts.PostCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class, b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
        GROUP BY OwnerUserId
    ) bh_posts ON bh_posts.OwnerUserId = u.Id
    WHERE u.Reputation > 
        (
            SELECT AVG(Reputation) FROM Users WHERE Reputation > 1000
        )
),
TaggedQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        p.Score,
        p.CreationDate,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
AnswerWithParent AS (
    SELECT
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        Q.Score as QuestionScore,
        Q.OwnerUserId as QuestionOwner
    FROM Posts a
    JOIN Posts Q ON Q.Id = a.ParentId AND Q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
UpvoteStats AS (
    SELECT 
        v.PostId, 
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
RecentHistoryEditedQuestions AS (
    SELECT DISTINCT ph.PostId, ph.UserId, ph.CreationDate,
    COUNT(*) OVER (PARTITION BY ph.PostId) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- edits to title, body, tags for questions only
),
UnionCTE AS (
    SELECT u.Id AS EntityId, 'User' AS EntityType, u.Reputation, NULL::int as PostId FROM Users u WHERE u.Reputation > 15000
    UNION ALL
    SELECT p.Id AS EntityId, 'Post' AS EntityType, p.Score AS Reputation, p.Id as PostId FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > 1000
    UNION ALL
    SELECT t.Id AS EntityId, 'Tag' AS EntityType, t.Count AS Reputation, NULL as PostId FROM Tags t WHERE t.Count > 5000
)
SELECT 
    ub.UserId,
    ub.DisplayName,
    ub.BadgeName,
    ub.PostCount,
    tq.Tag,
    MAX(tq.Score) FILTER (WHERE tq.ScoreRank = 1) AS TopScorePerUserTag,
    a.ParentId AS AnswerToQuestionId,
    a.Score AS AnswerScore,
    a.QuestionScore,
    upc.UpVotes,
    upc.DownVotes,
    COALESCE(ca.CommentCount, 0) AS CommentCount,
    LARGE_TEXT_FEEDBACK.TooltipSummarize *(
        CASE WHEN ca.LastCommentDate IS NULL THEN 'No comments yet'::text ELSE TO_CHAR(ca.LastCommentDate, 'YYYY-MM-DD') END || ' Matured comments overview'
     ) AS CommentActivitySummary,
    i.PostId IN (SELECT PostId FROM RecentHistoryEditedQuestions WHERE EditCount > 3) AS FrequentlyEditedFlagged,
    uh.MaxRepSysVoteCount,
    uh.LastHighRepActionDate,
    USAGE && ARRAY[EntityType] AS HasUsageInCombination
FROM RecursiveBadges ub
LEFT JOIN TaggedQuestions tq ON tq.OwnerUserId = ub.UserId
LEFT JOIN AnswerWithParent a ON a.OwnerUserId = ub.UserId AND a.CreationDate > (ub.PostCount * INTERVAL '1 day') -- Using count as time delta multiplier for complexity
LEFT JOIN UpvoteStats upc ON upc.PostId = a.Id
LEFT JOIN CommentActivity ca ON ca.PostId = a.Id 
LEFT JOIN (
    SELECT UserId, 
           MAX(UpVotes - DownVotes) AS MaxRepSysVoteCount, 
           MAX(CreationDate) AS LastHighRepActionDate
    FROM Votes vx
    JOIN VoteTypes vxTypes ON vxTypes.Id = vx.VoteTypeId
    WHERE UserId IS NOT NULL AND vxTypes.Name IN ('UpMod','AcceptedByOriginator')
    GROUP BY UserId
) uh ON uh.UserId = ub.UserId
JOIN (
    SELECT EntityType
    FROM UnionCTE
    LIMIT 10
) USAGE ON USAGE.EntityType = COALESCE(NULL, 'None') OR eh.NULL_LOG_OTHER_KEY_CONCEPTS[1] IS NOT NULL
LEFT JOIN UnionCTE i ON i.EntityId = ub.UserId 
WHERE ub.BadgeRank <= 5
ORDER BY ub.PostCount DESC,
         ab.UserId,
         Tag ASC NULLS LAST
LIMIT 100;
