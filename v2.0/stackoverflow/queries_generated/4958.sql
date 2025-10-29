-- {"query": "4958.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1386} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY YEAR(u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AveragePostScore,
        MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastPostDate,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextHighestReputation
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        PostCount,
        QuestionCount,
        AnswerCount,
        ReputationRank,
        YearlyReputationRank,
        AveragePostScore,
        LastPostDate,
        NextHighestReputation
    FROM
        RankedUserActivity
    WHERE
        ReputationRank <= 1000
),
PostWithComments AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        STRING_AGG(SUBSTRING(c.Text, 1, 50), ' | ' ORDER BY c.CreationDate) AS SnippetOfComments
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName,
        CASE
            WHEN lt.Name = 'Linked' THEN 1
            WHEN lt.Name = 'Duplicate' THEN 2
            ELSE 0
        END AS LinkTypeCategory
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
)
SELECT
    hru.DisplayName,
    hru.Reputation,
    hru.UserCreationDate,
    hru.PostCount,
    hru.QuestionCount,
    hru.AnswerCount,
    hru.ReputationRank,
    hru.YearlyReputationRank,
    hru.AveragePostScore,
    hru.LastPostDate,
    hru.NextHighestReputation,
    COUNT(pwc.PostId) AS PostsWithComments,
    SUM(pwc.CommentCount) AS TotalCommentsOnPosts,
    AVG(pwc.TotalCommentScore) AS AverageCommentScore,
    COUNT(pla.PostId) FILTER (WHERE pla.LinkTypeCategory = 1) AS LinkedPosts,
    COUNT(pla.PostId) FILTER (WHERE pla.LinkTypeCategory = 2) AS DuplicateLinks,
    CASE
        WHEN hru.DisplayName LIKE '%[^a-zA-Z0-9]%' THEN 'Contains Special Characters'
        WHEN hru.DisplayName ~* '.*[aeiou]{2}.*' THEN 'Consecutive Vowels'
        ELSE 'Standard Name'
    END AS DisplayNamePattern,
    COALESCE(hru.UserCreationDate, '1970-01-01') AS EffectiveCreationDate,
    DATEDIFF(day, hru.UserCreationDate, GETDATE()) AS UserAgeInDays,
    (hru.Reputation * 1.0 / NULLIF(hru.PostCount, 0)) AS ReputationPerPost,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = hru.UserId AND b.Class = 1) AS GoldBadgeCount,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.UserId = hru.UserId AND ph.PostHistoryTypeId IN (2, 5) -- Edit Body
    ) AS LastBodyEditDate
FROM
    HighReputationUsers hru
LEFT JOIN
    PostWithComments pwc ON hru.UserId = pwc.OwnerUserId
LEFT JOIN
    PostLinkAnalysis pla ON hru.UserId = pla.PostId
WHERE
    hru.Reputation > 10000
    AND YEAR(hru.UserCreationDate) < YEAR(GETDATE()) - 1
    AND hru.AveragePostScore IS NOT NULL
    AND hru.DisplayName NOT LIKE '%[^a-zA-Z ]%' -- Filter for names with only letters and spaces
GROUP BY
    hru.UserId, hru.DisplayName, hru.Reputation, hru.UserCreationDate, hru.PostCount, hru.QuestionCount, hru.AnswerCount, hru.ReputationRank, hru.YearlyReputationRank, hru.AveragePostScore, hru.LastPostDate, hru.NextHighestReputation
HAVING
    COUNT(pwc.PostId) > 5
    OR COUNT(pla.PostId) > 0
ORDER BY
    hru.Reputation DESC, hru.UserCreationDate ASC;
