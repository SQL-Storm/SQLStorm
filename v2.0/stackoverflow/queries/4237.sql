-- {"query": "4237.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1095}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) AS RankByReputationAndActivity
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.CreationDate >= cast('2024-10-01' as date) - INTERVAL '5 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighActivityUsers AS (
    SELECT UserId, DisplayName, Reputation, PostCount, QuestionCount, AnswerCount
    FROM RankedUserActivity
    WHERE RankByReputationAndActivity <= 500
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END
),
UserPostEngagement AS (
    SELECT
        hau.UserId,
        hau.DisplayName,
        hau.Reputation,
        pe.PostId,
        pe.Title,
        pe.Score,
        pe.CommentCount,
        pe.UpVoteCount,
        pe.DownVoteCount,
        pe.PostStatus,
        ROW_NUMBER() OVER (PARTITION BY hau.UserId ORDER BY pe.Score DESC, pe.UpVoteCount DESC) AS PostEngagementRank
    FROM HighActivityUsers hau
    JOIN Posts p ON hau.UserId = p.OwnerUserId
    JOIN PostEngagement pe ON p.Id = pe.PostId
    WHERE pe.CommentCount > 0 OR pe.UpVoteCount > 0
)
SELECT
    ha.DisplayName AS HighActivityUser,
    ha.Reputation,
    ha.PostCount,
    ha.QuestionCount,
    ha.AnswerCount,
    upe.Title AS TopPostTitle,
    upe.Score AS TopPostScore,
    upe.CommentCount AS TopPostCommentCount,
    upe.UpVoteCount AS TopPostUpVoteCount,
    upe.DownVoteCount AS TopPostDownVoteCount,
    upe.PostStatus AS TopPostStatus,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = ha.UserId AND b.Class = 1
        ),
        0
    ) AS GoldBadgeCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            JOIN Posts p_rel ON pl.RelatedPostId = p_rel.Id
            WHERE pl.PostId = upe.PostId AND pl.LinkTypeId = 3 AND p_rel.OwnerUserId = ha.UserId
        ),
        0
    ) AS DuplicateLinksToOwnPosts
FROM HighActivityUsers ha
LEFT JOIN UserPostEngagement upe ON ha.UserId = upe.UserId AND upe.PostEngagementRank = 1
WHERE ha.Reputation > 100000
UNION ALL
SELECT
    NULL AS HighActivityUser,
    NULL AS Reputation,
    NULL AS PostCount,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    pe.Title AS TopPostTitle,
    pe.Score AS TopPostScore,
    pe.CommentCount AS TopPostCommentCount,
    pe.UpVoteCount AS TopPostUpVoteCount,
    pe.DownVoteCount AS TopPostDownVoteCount,
    pe.PostStatus AS TopPostStatus,
    0 AS GoldBadgeCount,
    0 AS DuplicateLinksToOwnPosts
FROM PostEngagement pe
WHERE pe.Score > 1000 AND pe.CommentCount > 50
ORDER BY Reputation DESC NULLS LAST, TopPostScore DESC NULLS LAST;