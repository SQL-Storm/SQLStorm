-- {"query": "22050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1138} 
WITH user_post_stats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN LENGTH(COALESCE(p.Title, '')) ELSE NULL END) AS AvgQuestionTitleLength,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.Score, 0) ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.Score, 0) ELSE 0 END) AS TotalAnswerScore
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
),
user_badge_points AS (
    SELECT 
        UserId,
        SUM(CASE 
            WHEN Class = 1 THEN 10 
            WHEN Class = 2 THEN 5 
            WHEN Class = 3 THEN 1 
            ELSE 0 
        END) AS BadgePoints,
        COUNT(*) AS TotalBadges,
        STRING_AGG(Name, ', ' ORDER BY Date) AS BadgeList
    FROM Badges
    GROUP BY UserId
),
user_vote_stats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.Id END) AS AcceptedAnswers
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id
),
ranked_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ups.QuestionCount, 0) AS QuestionCount,
        COALESCE(ups.AnswerCount, 0) AS AnswerCount,
        COALESCE(ups.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(ups.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(ups.AvgQuestionTitleLength, 0) AS AvgQuestionTitleLength,
        COALESCE(ubp.BadgePoints, 0) AS BadgePoints,
        COALESCE(ubp.TotalBadges, 0) AS TotalBadges,
        COALESCE(uvs.TotalVotesReceived, 0) AS TotalVotesReceived,
        COALESCE(uvs.UpVotes, 0) AS UpVotes,
        COALESCE(uvs.DownVotes, 0) AS DownVotes,
        COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswers,
        CASE 
            WHEN ups.QuestionCount > 0 AND ups.AnswerCount > 0 THEN 
                (COALESCE(ups.TotalQuestionScore, 0) * 2 + COALESCE(ups.TotalAnswerScore, 0)) / NULLIF(ups.QuestionCount + ups.AnswerCount, 0) * 
                (1 + LOG(1 + COALESCE(ubp.BadgePoints, 0)) + COALESCE(uvs.UpVotes, 0) / NULLIF(COALESCE(uvs.UpVotes, 0) + COALESCE(uvs.DownVotes, 0), 0))
            ELSE 0 
        END AS ComplexScore
    FROM Users u
    FULL OUTER JOIN user_post_stats ups ON u.Id = ups.UserId
    FULL OUTER JOIN user_badge_points ubp ON u.Id = ubp.UserId
    FULL OUTER JOIN user_vote_stats uvs ON u.Id = uvs.UserId
),
final_ranked AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY ComplexScore DESC, Reputation DESC) AS GlobalRank,
        ROW_NUMBER() OVER (ORDER BY ComplexScore DESC) AS ScoreRank
    FROM ranked_users
)
SELECT 
    fr.Id,
    fr.DisplayName,
    fr.Reputation,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.TotalQuestionScore,
    fr.TotalAnswerScore,
    fr.AvgQuestionTitleLength,
    fr.BadgePoints,
    fr.TotalBadges,
    fr.TotalVotesReceived,
    fr.UpVotes,
    fr.DownVotes,
    fr.AcceptedAnswers,
    fr.ComplexScore,
    fr.GlobalRank,
    fr.ScoreRank,
    CASE 
        WHEN fr.TotalBadges > 0 THEN SUBSTRING(ubp.BadgeList FROM 1 FOR 100) || '...' 
        ELSE NULL 
    END AS PartialBadgeList
FROM final_ranked fr
LEFT OUTER JOIN user_badge_points ubp ON fr.Id = ubp.UserId
WHERE EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = fr.Id 
    AND p.CreationDate > '2008-01-01' 
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.Score > 0
    )
)
ORDER BY fr.GlobalRank ASC
LIMIT 100;