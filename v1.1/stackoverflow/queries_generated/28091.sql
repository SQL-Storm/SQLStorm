-- {"query": "28091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1938} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserSince,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        (SELECT AVG(AnswerCount) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) AS AvgAnswersPerQuestion
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate > '2010-01-01'
    GROUP BY u.Id
),
RankedBadges AS (
    SELECT 
        UserId,
        Name AS BadgeName,
        Date AS BadgeDate,
        Class,
        ROW_NUMBER() OVER (PARTITION BY Class ORDER BY Date DESC) AS BadgeRank
    FROM Badges
    WHERE Class IN (1, 2, 3)
),
PostAnalysis AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        ph.CreationDate AS LastEditDate,
        ph.PostHistoryTypeId,
        LEAD(ph.CreationDate) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS NextEditDate,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        (SELECT STRING_AGG(TagName, ', ' ORDER BY TagName) 
         FROM Tags 
         WHERE POSITION(TagName IN p.Tags) > 0) AS ResolvedTags
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    EXTRACT(YEAR FROM ua.UserSince) AS JoinYear,
    rb.BadgeName,
    rb.Class AS BadgeClass,
    pa.ResolvedTags,
    (ua.TotalVotes * 1.0) / NULLIF(ua.TotalPosts, 0) AS VotesPerPostRatio,
    (ua.UpVotes - ua.DownVotes) * 100.0 / NULLIF(ua.UpVotes + ua.DownVotes, 0) AS VoteEffectiveness,
    CASE 
        WHEN ua.Reputation > 100000 THEN 'Legendary'
        WHEN ua.Reputation > 50000 THEN 'Epic'
        WHEN ua.Reputation > 10000 THEN 'Advanced'
        ELSE 'Standard'
    END AS ReputationTier,
    DATE_PART('day', ua.LastAccessDate - ua.UserSince) AS DaysActive,
    pa.CommentCount,
    pa.Score AS PostScore,
    COALESCE(pa.NextEditDate, pa.LastEditDate + INTERVAL '7 days') AS ExpectedNextEdit,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND LinkTypeId = 3) AS DuplicateLinks
FROM UserActivity ua
JOIN RankedBadges rb ON ua.UserId = rb.UserId AND rb.BadgeRank = 1
LEFT JOIN PostAnalysis pa ON ua.UserId = pa.OwnerUserId
WHERE 
    ua.TotalPosts > 10 
    AND (ua.AnswersProvided > 5 OR ua.QuestionsAsked > 3)
    AND (pa.ResolvedTags LIKE '%sql%' OR pa.ResolvedTags LIKE '%performance%')
    AND pa.PostScore > 10
ORDER BY 
    ua.Reputation DESC, 
    DaysActive DESC, 
    pa.CommentCount DESC
LIMIT 100;
