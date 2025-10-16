-- {"query": "29005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2345} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END AS PostType,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (1, 5, 8, 9)) AS OtherVoteCount,
        COALESCE(
            (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10),
            p.ClosedDate
        ) AS CloseDate,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'VeryLowVoted'
        END AS VotingTier,
        CASE 
            WHEN CHARINDEX('http', p.Body) > 0 THEN 'ContainsLinks'
            WHEN CHARINDEX('code', LOWER(p.Body)) > 0 THEN 'ContainsCode'
            ELSE 'NoSpecialContent'
        END AS ContentCategory
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE POSITION('<' || t.TagName || '>' IN p.Tags) > 0) AS RelatedPostCount
    FROM Tags t
    WHERE t.Count > 100
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.CommentCount,
    ua.BadgeCount,
    CASE 
        WHEN ua.PostCount > 100 THEN 'HighlyActive'
        WHEN ua.PostCount > 50 THEN 'Active'
        WHEN ua.PostCount > 10 THEN 'Moderate'
        ELSE 'LowActivity'
    END AS ActivityLevel,
    (SELECT STRING_AGG(pa.Title, ', ') 
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 1 
     AND pa.Score > 10
     ORDER BY pa.CreationDate DESC
     LIMIT 5) AS TopQuestions,
    (SELECT STRING_AGG(pa.Title, ', ') 
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 2 
     AND pa.Score > 5
     ORDER BY pa.CreationDate DESC
     LIMIT 3) AS TopAnswers,
    (SELECT STRING_AGG(CONCAT('Tag:', ta.TagName, ' Count:', ta.TagCount), '; ')
     FROM TagAnalysis ta
     WHERE ta.RelatedPostCount > 10
     ORDER BY ta.TagCount DESC
     LIMIT 5) AS PopularTags,
    (
        SELECT COUNT(*) FROM Votes v 
        JOIN PostAnalysis pa ON v.PostId = pa.PostId 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId IN (1, 2, 3) 
        AND pa.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 YEAR')
    ) AS RecentVotes,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.OwnerUserId = ua.UserId 
        AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 DAYS')
    ) AS RecentPosts,
    (
        SELECT COUNT(DISTINCT v.PostId) FROM Votes v 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId = 1
    ) AS AcceptedAnswers,
    COALESCE(
        (SELECT CONCAT('Reputation Change: ', 
            (SELECT SUM(u1.UpVotes) - SUM(u1.DownVotes) - (SELECT SUM(u2.UpVotes) - SUM(u2.DownVotes) FROM Users u2 WHERE u2.Id = u.Id AND u2.CreationDate < u.CreationDate)
            FROM Users u1 
            WHERE u1.Id = u.Id)
        ) 
        FROM Users u 
        WHERE u.Id = ua.UserId), 
        'No Calculation'
    ) AS ReputationChange,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 3) AS BronzeBadges,
    (SELECT STRING_AGG(CONCAT(pa.Title, ' (Score: ', pa.Score, ')'), ', ')
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 1 
     AND pa.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
     ORDER BY pa.Score DESC
     LIMIT 5) AS YearlyTopQuestions
FROM UserActivity ua
INNER JOIN (
    SELECT UserId, COUNT(*) as activity_count
    FROM (
        SELECT OwnerUserId as UserId FROM Posts WHERE CreationDate >= '2020-01-01'
        UNION ALL
        SELECT UserId FROM Comments WHERE CreationDate >= '2020-01-01'
    ) user_activities
    GROUP BY UserId
    HAVING COUNT(*) > 5
) filtered_users ON ua.UserId = filtered_users.UserId
WHERE ua.Reputation > 5000
AND ua.PostCount > 10
ORDER BY ua.Reputation DESC
LIMIT 100
EXCEPT
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.CommentCount,
    ua.BadgeCount,
    CASE 
        WHEN ua.PostCount > 100 THEN 'HighlyActive'
        WHEN ua.PostCount > 50 THEN 'Active'
        WHEN ua.PostCount > 10 THEN 'Moderate'
        ELSE 'LowActivity'
    END AS ActivityLevel,
    (SELECT STRING_AGG(pa.Title, ', ') 
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 1 
     AND pa.Score > 10
     ORDER BY pa.CreationDate DESC
     LIMIT 5) AS TopQuestions,
    (SELECT STRING_AGG(pa.Title, ', ') 
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 2 
     AND pa.Score > 5
     ORDER BY pa.CreationDate DESC
     LIMIT 3) AS TopAnswers,
    (SELECT STRING_AGG(CONCAT('Tag:', ta.TagName, ' Count:', ta.TagCount), '; ')
     FROM TagAnalysis ta
     WHERE ta.RelatedPostCount > 10
     ORDER BY ta.TagCount DESC
     LIMIT 5) AS PopularTags,
    (
        SELECT COUNT(*) FROM Votes v 
        JOIN PostAnalysis pa ON v.PostId = pa.PostId 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId IN (1, 2, 3) 
        AND pa.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 YEAR')
    ) AS RecentVotes,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.OwnerUserId = ua.UserId 
        AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 DAYS')
    ) AS RecentPosts,
    (
        SELECT COUNT(DISTINCT v.PostId) FROM Votes v 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId = 1
    ) AS AcceptedAnswers,
    COALESCE(
        (SELECT CONCAT('Reputation Change: ', 
            (SELECT SUM(u1.UpVotes) - SUM(u1.DownVotes) - (SELECT SUM(u2.UpVotes) - SUM(u2.DownVotes) FROM Users u2 WHERE u2.Id = u.Id AND u2.CreationDate < u.CreationDate)
            FROM Users u1 
            WHERE u1.Id = u.Id)
        ) 
        FROM Users u 
        WHERE u.Id = ua.UserId), 
        'No Calculation'
    ) AS ReputationChange,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 3) AS BronzeBadges,
    (SELECT STRING_AGG(CONCAT(pa.Title, ' (Score: ', pa.Score, ')'), ', ')
     FROM PostAnalysis pa 
     WHERE pa.OwnerUserId = ua.UserId 
     AND pa.PostTypeId = 1 
     AND pa.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
     ORDER BY pa.Score DESC
     LIMIT 5) AS YearlyTopQuestions
FROM UserActivity ua
WHERE ua.Reputation < 1000
AND ua.PostCount < 5
ORDER BY ua.Reputation ASC
LIMIT 50;