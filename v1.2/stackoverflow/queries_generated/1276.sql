-- {"query": "1276.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1358} 

WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionViews,
        SUM(COALESCE(vt_up.UpVotesCount,0)) AS TotalUpVotesReceived,
        SUM(COALESCE(vt_down.DownVotesCount,0)) AS TotalDownVotesReceived,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        -- Window function for rank by reputation in location
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
      SELECT v.PostId, COUNT(*) AS UpVotesCount
      FROM Votes v
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
      WHERE vt.Name = 'UpMod'
      GROUP BY v.PostId
    ) vt_up ON vt_up.PostId = p.Id
    LEFT JOIN (
      SELECT v.PostId, COUNT(*) AS DownVotesCount
      FROM Votes v
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
      WHERE vt.Name = 'DownMod'
      GROUP BY v.PostId
    ) vt_down ON vt_down.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
), RankedQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        pHistCount.CloseVoteCount,
        pHistMaxLateEdit.LastEditDate,
        EXISTS (
            SELECT 1 FROM PostLinks pl
            WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3 -- Duplicate links
        ) AS IsDuplicateQuestion,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS GlobalQuestionRank
    FROM Posts q
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CloseVoteCount
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    ) pHistCount ON pHistCount.PostId = q.Id
    LEFT JOIN (
        SELECT PostId, MAX(LastEditDate) AS LastEditDate
        FROM Posts
        WHERE LastEditDate IS NOT NULL
        GROUP BY PostId
    ) pHistMaxLateEdit ON pHistMaxLateEdit.PostId = q.Id
    WHERE q.PostTypeId = 1
), ComplexTagSplit AS (
    SELECT
        q.QuestionId,
        unnest(string_to_array(regexp_replace(q.Tags, '[<>]', '', 'g' )),';') AS Tag
    FROM RankedQuestions q
), QuestionWithDuplicateAnswers AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS AnswerCount,
        COUNT(d.Id) AS DuplicateAnswersCount,
        ROUND(AVG(a.Score)::numeric, 2) AS AvgAnswerScore
    FROM RankedQuestions q
    LEFT JOIN Posts a 
        ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
    LEFT JOIN Posts d 
        ON d.ParentId = q.QuestionId AND d.PostTypeId = 2
        AND d.Id IN (
            SELECT RelatedPostId FROM PostLinks pl 
            WHERE pl.LinkTypeId = 3
        )
    GROUP BY q.QuestionId
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.LocationReputationRank,
    u.QuestionCount,
    u.AnswerCount,
    u.AvgPostScore,
    u.MaxQuestionViews,
    u.TotalUpVotesReceived,
    u.TotalDownVotesReceived,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    q.QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionCreationDate,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViews,
    q.CloseVoteCount,
    q.LastEditDate,
    q.IsDuplicateQuestion,
    q.GlobalQuestionRank,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.DuplicateAnswersCount,
    STRING_AGG(DISTINCT ctag.Tag, ',' ORDER BY ctag.Tag) AS QuestionTags
FROM UserPostStats u
LEFT JOIN RankedQuestions q ON q.OwnerUserId = u.UserId
LEFT JOIN QuestionWithDuplicateAnswers qa ON qa.QuestionId = q.QuestionId
LEFT JOIN ComplexTagSplit ctag ON ctag.QuestionId = q.QuestionId
WHERE u.Reputation > 1000
  AND (q.Score > 10 OR q.CloseVoteCount > 0)
  AND (u.GoldBadges + u.SilverBadges + u.BronzeBadges) > 2
GROUP BY
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.LocationReputationRank,
    u.QuestionCount,
    u.AnswerCount,
    u.AvgPostScore,
    u.MaxQuestionViews,
    u.TotalUpVotesReceived,
    u.TotalDownVotesReceived,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.CloseVoteCount,
    q.LastEditDate,
    q.IsDuplicateQuestion,
    q.GlobalQuestionRank,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.DuplicateAnswersCount
ORDER BY u.Reputation DESC, q.QuestionScore DESC, q.ViewCount DESC
LIMIT 100;
