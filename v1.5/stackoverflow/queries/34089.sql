-- {"query": "34089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1604} 
WITH UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate))/86400) AS UserAgeDays,
        u.Reputation,
        u.Location
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
RecentHighScoreQuestions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        substring(p.Tags from 2 for char_length(p.Tags) - 2) AS RawTags,
        array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ', ') AS TagList
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 5
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionWithAnswerStats AS (
    SELECT
        q.PostId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.RawTags,
        q.TagList,
        COALESCE(a.TotalAnswers,0) AS TotalAnswers,
        COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore,0) AS MaxAnswerScore,
        COALESCE(a.TotalUpVotes,0) AS TotalAnswerUpVotes,
        COALESCE(a.TotalDownVotes,0) AS TotalAnswerDownVotes
    FROM RecentHighScoreQuestions q
    LEFT JOIN AnswerStats a ON a.QuestionId = q.PostId
),
UserActivity AS (
    SELECT
        ph.UserId,
        COUNT(*) AS EditActions,
        COUNT(DISTINCT ph.PostId) AS EditedPosts,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)
    GROUP BY ph.UserId
),
TopUsersByActivity AS (
    SELECT
        ubs.UserId,
        ubs.DisplayName,
        ubs.Reputation,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TotalBadges,
        ua.EditActions,
        ua.EditedPosts,
        ua.LastEditDate,
        ubs.UserAgeDays,
        ubs.Location
    FROM UserBadgeSummary ubs
    JOIN UserActivity ua ON ua.UserId = ubs.UserId
    WHERE ubs.TotalBadges > 10 AND ua.EditActions > 20
),
PopularQuestionsWithActiveEditors AS (
    SELECT
        q.PostId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.TagList,
        q.TotalAnswers,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.TotalAnswerUpVotes,
        q.TotalAnswerDownVotes,
        COUNT(DISTINCT ph.UserId) AS ActiveEditors
    FROM QuestionWithAnswerStats q
    LEFT JOIN PostHistory ph ON ph.PostId = q.PostId AND ph.UserId IS NOT NULL AND ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    WHERE q.ViewCount > 1000 AND q.AnswerCount > 2
    GROUP BY q.PostId, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.TagList, q.TotalAnswers, q.AvgAnswerScore, q.MaxAnswerScore, q.TotalAnswerUpVotes, q.TotalAnswerDownVotes
),
UserAnswerCorrelations AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS AnswersWritten,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(vote_up.CountUpVotes) AS TotalUpVotes,
        SUM(vote_down.CountDownVotes) AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountUpVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) vote_up ON vote_up.PostId = a.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountDownVotes
        FROM Votes
        WHERE VoteTypeId = 3
        GROUP BY PostId
    ) vote_down ON vote_down.PostId = a.Id
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(a.Id) > 5
)
SELECT
    pq.PostId,
    pq.Title,
    pq.QuestionScore,
    pq.ViewCount,
    pq.AnswerCount,
    pq.TagList,
    pq.TotalAnswers,
    pq.AvgAnswerScore,
    pq.MaxAnswerScore,
    pq.TotalAnswerUpVotes,
    pq.TotalAnswerDownVotes,
    pq.ActiveEditors,
    tuba.UserId,
    tuba.DisplayName AS TopAnswerer,
    tuba.AnswersWritten,
    ROUND(tuba.AvgAnswerScore,2) AS AvgAnswerScoreByUser,
    tuba.MaxAnswerScore AS MaxAnswerScoreByUser,
    tuba.TotalUpVotes AS UserUpVotes,
    tuba.TotalDownVotes AS UserDownVotes,
    ua.EditActions AS UserEditActions,
    ua.EditedPosts AS UserEditedPosts,
    ua.LastEditDate AS UserLastEditDate,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.Reputation,
    ubs.UserAgeDays,
    ubs.Location
FROM PopularQuestionsWithActiveEditors pq
LEFT JOIN UserAnswerCorrelations tuba ON tuba.UserId = (
    SELECT a.OwnerUserId
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.ParentId = pq.PostId
    ORDER BY a.Score DESC
    LIMIT 1
)
LEFT JOIN TopUsersByActivity ua ON ua.UserId = tuba.UserId
LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = tuba.UserId
WHERE pq.ActiveEditors > 3
ORDER BY pq.ViewCount DESC, pq.QuestionScore DESC
LIMIT 100;