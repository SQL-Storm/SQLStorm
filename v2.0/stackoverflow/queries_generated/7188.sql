-- {"query": "7188.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1620} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId) 
            THEN 'AboveAverage' 
            ELSE 'BelowAverage' 
        END AS ScorePerformance,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND Score > 0)
            ELSE 0 
        END AS ValuableAnswers
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' 
      AND p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.Score), 0) AS AvgScore,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title END, '; ') AS QuestionTitles,
        STRING_AGG(CASE WHEN p.PostTypeId = 2 THEN p.Body END, '; ') AS AnswerBodies
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        COALESCE(p.Title, 'No Title') AS ExcerptTitle,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular' 
            ELSE 'Moderate' 
        END AS TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
),
QuestionStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountActual,
        CASE 
            WHEN q.AnswerCount > 0 THEN 
                (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = q.Id)
            ELSE NULL 
        END AS AvgAnswerScore,
        CASE 
            WHEN q.OwnerUserId IS NOT NULL THEN 
                (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = q.OwnerUserId AND p.PostTypeId = 1)
            ELSE 0 
        END AS OwnerQuestionCount,
        NULLIF(q.AnswerCount, 0) / NULLIF(q.ViewCount, 0) AS AnswerToViewRatio,
        GREATEST(q.Score, 0) + COALESCE((SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 8), 0) AS AdjustedScore
    FROM Posts q
    WHERE q.PostTypeId = 1
)
SELECT 
    rs.Id AS PostId,
    rs.PostTypeId,
    rs.OwnerUserId,
    rs.Score,
    rs.ViewCount,
    rs.Title,
    rs.AnswerCount,
    rs.CommentCount,
    rs.FavoriteCount,
    rs.PrevScore,
    rs.UserPostRank,
    rs.TotalUserPosts,
    rs.AvgUserScore,
    rs.ScorePerformance,
    rs.ValuableAnswers,
    us.DisplayName AS OwnerName,
    us.Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.LastPostDate,
    us.TotalScore,
    us.AvgScore,
    ta.TagName,
    ta.Count AS TagCount,
    ta.ExcerptTitle,
    ta.TagPopularity,
    ta.PopularityRank,
    qs.QuestionId,
    qs.AnswerCount AS QuestionAnswerCount,
    qs.CommentCountActual,
    qs.AvgAnswerScore,
    qs.OwnerQuestionCount,
    qs.AnswerToViewRatio,
    qs.AdjustedScore,
    CASE 
        WHEN rs.Score > 0 AND rs.ViewCount > 0 THEN (rs.Score * 1.0 / rs.ViewCount) 
        ELSE 0 
    END AS ScorePerView,
    CASE 
        WHEN rs.Score > rs.PrevScore THEN 'Increased' 
        WHEN rs.Score < rs.PrevScore THEN 'Decreased' 
        ELSE 'Stable' 
    END AS ScoreChangeStatus,
    CASE 
        WHEN rs.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveGlobalAverage' 
        ELSE 'BelowGlobalAverage' 
    END AS GlobalScoreRanking
FROM RankedPosts rs
LEFT JOIN UserStats us ON rs.OwnerUserId = us.UserId
LEFT JOIN (
    SELECT 
        q.Id AS QuestionId,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.ExcerptPostId IS NOT NULL AS HasExcerpt
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT 
            unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    ) AS tags
    INNER JOIN Tags t ON tags.TagName = t.TagName
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND q.Tags != ''
) ta ON rs.Id = ta.QuestionId
LEFT JOIN QuestionStats qs ON rs.Id = qs.QuestionId
WHERE EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = rs.OwnerUserId 
      AND p.CreationDate BETWEEN '2020-01-01' AND '2024-12-31'
)
  AND rs.Score IS NOT NULL 
  AND rs.ViewCount >= 100
  AND (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.OwnerUserId = rs.OwnerUserId 
      AND p.PostTypeId = 1 
      AND p.CreationDate > '2020-01-01'
  ) > 5
ORDER BY rs.Score DESC, rs.ViewCount DESC
LIMIT 1000;