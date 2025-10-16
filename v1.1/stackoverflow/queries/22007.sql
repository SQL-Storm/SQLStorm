-- {"query": "22007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1618} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views, 0) AS Views,
        u.CreationDate,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
        (SELECT COALESCE(SUM(v.BountyAmount), 0) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS TotalBountyOffered
    FROM Users u
),
BadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostDetails AS (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedQuestions,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
VoteStats AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
),
TopTags AS (
    SELECT
        p.OwnerUserId,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS TagString,
        (SELECT STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalBountyOffered,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    bs.BadgeNames,
    pd.AvgPostScore,
    pd.AcceptedQuestions,
    pd.MaxViewCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    (ua.Reputation + COALESCE(bs.TotalBadges * 10, 0) + COALESCE(pd.AcceptedQuestions * 15, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) AS ComplexScore,
    CASE
        WHEN ua.QuestionCount > 0 AND ua.AnswerCount > 0 THEN 'Balanced'
        WHEN ua.QuestionCount > ua.AnswerCount THEN 'Questioner'
        WHEN ua.AnswerCount > ua.QuestionCount THEN 'Answerer'
        ELSE 'Newbie'
    END AS UserType,
    ROW_NUMBER() OVER (ORDER BY (ua.Reputation + COALESCE(bs.TotalBadges * 10, 0) + COALESCE(pd.AcceptedQuestions * 15, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) DESC) AS Rank,
    LEAD(ua.DisplayName) OVER (ORDER BY ua.Reputation DESC) AS NextUserDisplayName,
    LAG(ua.Reputation) OVER (ORDER BY ua.Reputation DESC) AS PrevReputation,
    PERCENT_RANK() OVER (ORDER BY ua.Reputation) AS ReputationPercentile
FROM UserActivity ua
LEFT OUTER JOIN BadgeStats bs ON ua.UserId = bs.UserId
LEFT OUTER JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
LEFT OUTER JOIN VoteStats vs ON (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId ORDER BY p.Score DESC LIMIT 1) = vs.PostId
WHERE ua.Reputation > 1000
    AND (bs.GoldBadges > 0 OR bs.TotalBadges IS NULL)
    AND LENGTH(COALESCE(bs.BadgeNames, '')) > 0
    AND (pd.AvgPostScore IS NOT NULL AND pd.AvgPostScore > 0)
UNION
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalBountyOffered,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    bs.BadgeNames,
    pd.AvgPostScore,
    pd.AcceptedQuestions,
    pd.MaxViewCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    (ua.Reputation + COALESCE(bs.TotalBadges * 10, 0) + COALESCE(pd.AcceptedQuestions * 15, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) AS ComplexScore,
    CASE
        WHEN ua.QuestionCount > 0 AND ua.AnswerCount > 0 THEN 'Balanced'
        WHEN ua.QuestionCount > ua.AnswerCount THEN 'Questioner'
        WHEN ua.AnswerCount > ua.QuestionCount THEN 'Answerer'
        ELSE 'Newbie'
    END AS UserType,
    ROW_NUMBER() OVER (ORDER BY (ua.Reputation + COALESCE(bs.TotalBadges * 10, 0) + COALESCE(pd.AcceptedQuestions * 15, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) DESC) AS Rank,
    LEAD(ua.DisplayName) OVER (ORDER BY ua.Reputation DESC) AS NextUserDisplayName,
    LAG(ua.Reputation) OVER (ORDER BY ua.Reputation DESC) AS PrevReputation,
    PERCENT_RANK() OVER (ORDER BY ua.Reputation) AS ReputationPercentile
FROM UserActivity ua
LEFT OUTER JOIN BadgeStats bs ON ua.UserId = bs.UserId
LEFT OUTER JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
LEFT OUTER JOIN VoteStats vs ON (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId ORDER BY p.Score DESC LIMIT 1) = vs.PostId
WHERE ua.Reputation <= 1000
    AND bs.TotalBadges IS NULL
    AND pd.AcceptedQuestions IS NULL
ORDER BY Rank ASC
LIMIT 100;