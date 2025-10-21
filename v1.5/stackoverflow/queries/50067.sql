-- {"query": "50067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1261} 
WITH TagExperts AS (
    -- Step 1: Identify users who are experts in specific popular tags ('sql', 'python', 'java')
    -- based on a high score in answers related to those tags.
    SELECT
        p_ans.OwnerUserId AS UserId,
        CASE
            WHEN p_q.Tags LIKE '%<sql>%' THEN 'sql'
            WHEN p_q.Tags LIKE '%<python>%' THEN 'python'
            WHEN p_q.Tags LIKE '%<java>%' THEN 'java'
        END AS Tag,
        COUNT(*) AS AnswerCount,
        SUM(p_ans.Score) AS TotalAnswerScore
    FROM Posts p_ans
    JOIN Posts p_q ON p_ans.ParentId = p_q.Id
    WHERE p_ans.PostTypeId = 2 -- Answers
      AND p_q.PostTypeId = 1 -- Questions
      AND p_ans.OwnerUserId IS NOT NULL
      AND (p_q.Tags LIKE '%<sql>%' OR p_q.Tags LIKE '%<python>%' OR p_q.Tags LIKE '%<java>%')
    GROUP BY p_ans.OwnerUserId, Tag
    HAVING SUM(p_ans.Score) > 50 AND COUNT(*) > 5
),
UserEngagement AS (
    -- Step 2: Calculate overall user engagement metrics, such as badges, votes, and comments
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostRevisions AS (
    -- Step 3: Analyze how often experts' posts are revised by others
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(ph.Id) AS RevisionsByOthers,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))) / 3600 AS AvgTimeToFirstRevisionHours
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, or Tags
      AND ph.UserId != p.OwnerUserId -- Edited by someone else
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RankedExperts AS (
    -- Step 4: Combine the expert data with engagement metrics and rank them within each tag
    SELECT
        ue.DisplayName,
        ue.Reputation,
        te.Tag,
        te.AnswerCount,
        te.TotalAnswerScore,
        ue.GoldBadges,
        ue.UpvotesGiven,
        ue.CommentsMade,
        COALESCE(pr.RevisionsByOthers, 0) AS RevisionsByOthers,
        (te.TotalAnswerScore * 0.6 + ue.GoldBadges * 20 + ue.CommentsMade * 0.1 - COALESCE(pr.RevisionsByOthers, 0) * 0.5) AS WeightedScore,
        ROW_NUMBER() OVER(PARTITION BY te.Tag ORDER BY (te.TotalAnswerScore * 0.6 + ue.GoldBadges * 20) DESC, ue.Reputation DESC) as RankInTag
    FROM TagExperts te
    JOIN UserEngagement ue ON te.UserId = ue.UserId
    LEFT JOIN PostRevisions pr ON te.UserId = pr.UserId
)
-- Final Step: Select the top 3 experts for each tag, along with their detailed stats
-- and compare their score with the next-ranked user in their tag.
SELECT
    re.DisplayName,
    re.Tag,
    re.RankInTag,
    re.Reputation,
    re.WeightedScore,
    re.AnswerCount AS AnswersInTag,
    re.TotalAnswerScore,
    re.GoldBadges,
    re.UpvotesGiven,
    re.CommentsMade,
    re.RevisionsByOthers,
    (
        SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC)
        FROM Badges b
        WHERE b.UserId = (SELECT u.Id FROM Users u WHERE u.DisplayName = re.DisplayName LIMIT 1)
          AND b.Class = 1
        LIMIT 3
    ) AS RecentGoldBadges,
    LEAD(re.WeightedScore, 1, 0) OVER (PARTITION BY re.Tag ORDER BY re.RankInTag) AS NextRankScore,
    re.WeightedScore - LEAD(re.WeightedScore, 1, 0) OVER (PARTITION BY re.Tag ORDER BY re.RankInTag) AS ScoreLead
FROM RankedExperts re
WHERE re.RankInTag <= 3
ORDER BY re.Tag, re.RankInTag;