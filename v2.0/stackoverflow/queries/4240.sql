-- {"query": "4240.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1314}
WITH RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.CreationDate, 1, DATE '1900-01-01') OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN RUP.PostType = 'Question' THEN RUP.PostId END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN RUP.PostType = 'Answer' THEN RUP.PostId END) AS AnswerCount,
        SUM(CASE WHEN RUP.PostType = 'Answer' THEN GREATEST(0, p_ans.Score) ELSE 0 END) AS TotalAnswerScore,
        AVG(
            CASE
                WHEN RUP.PostType = 'Answer' THEN EXTRACT(EPOCH FROM (RUP.PostCreationDate - RUP.PreviousPostDate)) / 86400.0
            END
        ) AS AvgDaysBetweenAnswers,
        MAX(CASE WHEN RUP.PostType = 'Question' THEN RUP.PostRank ELSE 0 END) AS MaxQuestionRank,
        CASE
            WHEN COUNT(DISTINCT CASE WHEN RUP.PostType = 'Question' THEN RUP.PostId END) > 0 THEN
                (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Question%')
            ELSE 0
        END AS QuestionBadgeCount
    FROM Users u
    LEFT JOIN RankedUserPosts RUP ON u.Id = RUP.OwnerUserId
    LEFT JOIN Posts p_ans ON RUP.PostId = p_ans.Id AND RUP.PostType = 'Answer'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopContributors AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.AnswerCount,
        uas.TotalAnswerScore,
        (uas.TotalAnswerScore * 1.0) / NULLIF(uas.AnswerCount, 0) AS AvgAnswerScore,
        CASE
            WHEN uas.QuestionCount > 0 AND uas.AnswerCount > uas.QuestionCount THEN 'Prolific Answerer'
            WHEN uas.QuestionCount > 50 AND uas.AnswerCount < 10 THEN 'Primarily a Questioner'
            WHEN uas.Reputation > 100000 THEN 'High Reputation User'
            ELSE 'Standard Contributor'
        END AS ContributionCategory
    FROM UserActivitySummary uas
    WHERE uas.AnswerCount > 5 OR uas.QuestionCount > 5
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType,
        p1.Title AS SourcePostTitle,
        p2.Title AS TargetPostTitle,
        EXTRACT(EPOCH FROM (pl.CreationDate - p1.CreationDate)) / 86400.0 AS DaysFromPostToLink
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE lt.Name = 'Duplicate' AND EXTRACT(EPOCH FROM (pl.CreationDate - p1.CreationDate)) / 86400.0 BETWEEN 1 AND 30
)
SELECT
    tc.UserId,
    tc.DisplayName,
    tc.ContributionCategory,
    tc.Reputation,
    tc.AnswerCount,
    tc.AvgAnswerScore,
    COUNT(DISTINCT pla.PostId) AS DuplicateLinksCount,
    SUM(CASE WHEN pla.DaysFromPostToLink > 7 THEN 1 ELSE 0 END) AS LateDuplicateLinks,
    CASE
        WHEN MAX(p.Score) > 100 THEN 'Highly Scored Post'
        WHEN COUNT(c.Id) > 10 THEN 'Highly Commented Post'
        ELSE 'Standard Post Activity'
    END AS PostActivityLevel,
    COALESCE(SUM(CASE WHEN ph.Comment IS NOT NULL THEN 1 ELSE 0 END), 0) AS PostHistoryEntriesWithComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tc.UserId AND v.VoteTypeId = 2) AS UpVoteGivenCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tc.UserId AND v.VoteTypeId = 3) AS DownVoteGivenCount
FROM TopContributors tc
LEFT JOIN PostLinkAnalysis pla ON tc.UserId = pla.PostId
LEFT JOIN Posts p ON tc.UserId = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostHistory ph ON tc.UserId = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
GROUP BY
    tc.UserId,
    tc.DisplayName,
    tc.ContributionCategory,
    tc.Reputation,
    tc.AnswerCount,
    tc.AvgAnswerScore
HAVING
    COUNT(DISTINCT pla.PostId) > 0 OR tc.Reputation > 50000
ORDER BY
    tc.Reputation DESC,
    tc.AnswerCount DESC
LIMIT 100;