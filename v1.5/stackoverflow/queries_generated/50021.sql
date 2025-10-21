-- {"query": "50021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 878} 

WITH TagActivity AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CreationDate AS QuestionDate,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Is a Question
      AND p.ClosedDate IS NULL
      AND p.AnswerCount > 2
      AND p.Score > (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1)
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ta.TagName,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        EXTRACT(EPOCH FROM (a.CreationDate - ta.QuestionDate)) / 3600 AS HoursToAnswer,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerCommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS AnswerUpVotes,
        ROW_NUMBER() OVER(PARTITION BY ta.TagName, u.Id ORDER BY a.Score DESC, a.CreationDate DESC) AS rn
    FROM Users u
    JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    JOIN TagActivity ta ON a.ParentId = ta.QuestionId
    WHERE u.Reputation > 1000
      AND u.CreationDate < '2020-01-01'
),
RankedBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER(PARTITION BY b.UserId ORDER BY b.Date) AS BadgeRank
    FROM Badges b
    WHERE b.Class = 1 -- Gold Badges
)
SELECT
    uc.TagName,
    uc.UserId,
    uc.DisplayName,
    uc.Reputation,
    AVG(uc.AnswerScore) AS AvgAnswerScore,
    COUNT(uc.AnswerId) AS TotalAnswersInTag,
    SUM(uc.AnswerUpVotes) AS TotalUpVotesInTag,
    MAX(uc.AnswerCommentCount) AS MaxCommentsOnAnswer,
    MIN(uc.HoursToAnswer) AS QuickestAnswerHours,
    (
        SELECT STRING_AGG(rb.BadgeName, ', ')
        FROM RankedBadges rb
        WHERE rb.UserId = uc.UserId AND rb.BadgeRank <= 3
    ) AS FirstThreeGoldBadges,
    (
        SELECT ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostId = (
            SELECT p_inner.Id
            FROM Posts p_inner
            WHERE p_inner.OwnerUserId = uc.UserId AND p_inner.PostTypeId = 2
            ORDER BY p_inner.Score DESC
            LIMIT 1
        )
        AND ph.PostHistoryTypeId = 2 -- Initial Body
        LIMIT 1
    ) AS BestAnswerInitialPostDate
FROM UserContributions uc
WHERE uc.rn <= 10 -- Consider only top 10 answers per user per tag
GROUP BY uc.TagName, uc.UserId, uc.DisplayName, uc.Reputation
HAVING COUNT(uc.AnswerId) > 5 AND AVG(uc.AnswerScore) > 10
ORDER BY uc.TagName, TotalUpVotesInTag DESC, uc.Reputation DESC
LIMIT 500;
