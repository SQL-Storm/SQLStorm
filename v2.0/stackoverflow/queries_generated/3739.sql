-- {"query": "3739.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2681} 

WITH 
    q_posts AS (
        SELECT 
            p.Id,
            p.Title,
            p.CreationDate,
            p.OwnerUserId,
            p.Score,
            p.ViewCount,
            COALESCE(NULLIF(p.Tags,''),NULL) AS RawTags
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    tags_expanded AS (
        SELECT
            q.Id,
            q.Title,
            q.CreationDate,
            q.OwnerUserId,
            q.Score,
            q.ViewCount,
            TRIM(BOTH '><' FROM UNNEST(string_to_array(TRIM(BOTH '><' FROM q.RawTags), '><'))) AS Tag
        FROM q_posts q
        WHERE q.RawTags IS NOT NULL
    ),
    user_agg AS (
        SELECT 
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COALESCE(SUM(b.Class),0) AS BadgeScore,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    top_tags AS (
        SELECT 
            te.Tag,
            COUNT(*) AS TagUseCount,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS TagRank
        FROM tags_expanded te
        GROUP BY te.Tag
        HAVING COUNT(*) > 10
    ),
    answer_stats AS (
        SELECT 
            a.ParentId AS QuestionId,
            COUNT(*) AS AnswerCount,
            AVG(a.Score) AS AvgAnswerScore,
            MAX(a.Score) AS MaxAnswerScore,
            SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousAnswers
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),
    recent_votes AS (
        SELECT 
            v.PostId,
            v.VoteTypeId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS VoteSeq
        FROM Votes v
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),
    voted_posts AS (
        SELECT 
            rv.PostId,
            MAX(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasRecentUpvote,
            MAX(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasRecentDownvote
        FROM recent_votes rv
        GROUP BY rv.PostId
    )
SELECT 
    q.Id                                 AS QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    COALESCE(u.DisplayName,'Community')   AS OwnerName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.BadgeScore,
    t.Tag,
    t.TagUseCount,
    a.AnswerCount                         AS TotalAnswers,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    a.AnonymousAnswers,
    CASE 
        WHEN vp.HasRecentUpvote = 1   THEN 'Upvoted Recently'
        WHEN vp.HasRecentDownvote = 1 THEN 'Downvoted Recently'
        ELSE                               'No Recent Vote'
    END                                   AS RecentVoteStatus,
    ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS RankByScore
FROM q_posts q
LEFT JOIN user_agg u      ON u.UserId = q.OwnerUserId
LEFT JOIN tags_expanded te ON te.Id = q.Id
LEFT JOIN top_tags t      ON t.Tag = te.Tag
LEFT JOIN answer_stats a  ON a.QuestionId = q.Id
LEFT JOIN voted_posts vp  ON vp.PostId = q.Id
WHERE 
    (q.Score > 0 OR q.ViewCount > 1000)
    AND (t.TagRank IS NULL OR t.TagRank <= 5)
    AND (u.RepRank <= 100 OR u.BadgeScore > 0)
    AND (COALESCE(q.Tags,'') ILIKE '%<sql>%')
    AND NOT EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.PostId = q.Id 
          AND ph.PostHistoryTypeId = 12          -- deleted
    )
ORDER BY RankByScore
LIMIT 100
UNION ALL
SELECT 
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    'Deleted'                               AS OwnerName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Deleted Post'                          AS RecentVoteStatus,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RankByScore
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.Id NOT IN (SELECT Id FROM q_posts)
  AND p.CreationDate < CURRENT_DATE - INTERVAL '5 years'
ORDER BY RankByScore DESC
LIMIT 20;
