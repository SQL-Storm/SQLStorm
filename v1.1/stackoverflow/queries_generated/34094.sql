-- {"query": "34094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1184} 

WITH RankedAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        u.Id AS AnswererId,
        u.DisplayName AS AnswererName,
        u.Reputation AS AnswererReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    INNER JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 -- answers
), TopAnswers AS (
    SELECT *
    FROM RankedAnswers
    WHERE AnswerRank <= 3
), QuestionStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreation,
        q.OwnerUserId AS QuestionerId,
        qu.DisplayName AS QuestionerName,
        qu.Reputation AS QuestionerReputation,
        Tags,
        COALESCE(pht.Name, 'N/A') AS LastHistoryChangeType,
        ph.CreationDate AS LastHistoryChangeDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesOfQuestioner,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesOfQuestioner,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgesOfQuestioner
    FROM Posts q
    LEFT JOIN Users qu ON q.OwnerUserId = qu.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
    WHERE q.PostTypeId = 1 -- questions
    GROUP BY q.Id, qu.Id, pht.Id, ph.CreationDate
), TagExploded AS (
    SELECT
        qs.QuestionId,
        unnest(string_to_array(substring(qs.Tags, 2, length(qs.Tags) - 2), '><')) AS TagName,
        qs.Title,
        qs.QuestionScore,
        qs.ViewCount,
        qs.QuestionCreation,
        qs.QuestionerId,
        qs.QuestionerName,
        qs.QuestionerReputation,
        qs.LastHistoryChangeType,
        qs.LastHistoryChangeDate,
        qs.CommentCount,
        qs.UpVotesCount,
        qs.DownVotesCount,
        qs.GoldBadgesOfQuestioner,
        qs.SilverBadgesOfQuestioner,
        qs.BronzeBadgesOfQuestioner
    FROM QuestionStats qs
    WHERE qs.Tags IS NOT NULL AND qs.Tags != ''
), TagBadgeRanks AS (
    SELECT
        t.TagName,
        AVG(t.QuestionScore) AS AvgQuestionScore,
        AVG(t.ViewCount) AS AvgViews,
        AVG(t.QuestionerReputation) AS AvgQuestionerReputation,
        SUM(t.UpVotesCount) AS TotalUpVotes,
        SUM(t.DownVotesCount) AS TotalDownVotes,
        SUM(t.GoldBadgesOfQuestioner) AS TotalGoldBadges,
        SUM(t.SilverBadgesOfQuestioner) AS TotalSilverBadges,
        SUM(t.BronzeBadgesOfQuestioner) AS TotalBronzeBadges,
        COUNT(DISTINCT t.QuestionId) AS QuestionCount
    FROM TagExploded t
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT t.QuestionId) > 50
), FinalResults AS (
    SELECT 
        tbr.TagName,
        tbr.QuestionCount,
        tbr.AvgQuestionScore,
        tbr.AvgViews,
        tbr.AvgQuestionerReputation,
        tbr.TotalUpVotes,
        tbr.TotalDownVotes,
        tbr.TotalGoldBadges,
        tbr.TotalSilverBadges,
        tbr.TotalBronzeBadges,
        ARRAY_AGG(
            JSON_BUILD_OBJECT(
                'AnswerId', ta.AnswerId,
                'AnswerScore', ta.AnswerScore,
                'AnswerCreation', ta.AnswerCreation,
                'AnswererId', ta.AnswererId,
                'AnswererName', ta.AnswererName,
                'AnswererReputation', ta.AnswererReputation
            ) ORDER BY ta.AnswerScore DESC
        ) FILTER (WHERE ta.QuestionId IS NOT NULL) AS TopAnswers
    FROM TagBadgeRanks tbr
    LEFT JOIN TopAnswers ta ON ta.QuestionId IN (
        SELECT q.Id 
        FROM Posts q 
        WHERE q.PostTypeId = 1
        AND q.Tags LIKE '%' || tbr.TagName || '%'
    )
    GROUP BY tbr.TagName, tbr.QuestionCount, tbr.AvgQuestionScore, tbr.AvgViews, tbr.AvgQuestionerReputation, tbr.TotalUpVotes, tbr.TotalDownVotes, tbr.TotalGoldBadges, tbr.TotalSilverBadges, tbr.TotalBronzeBadges
)
SELECT *
FROM FinalResults
ORDER BY QuestionCount DESC, AvgQuestionScore DESC
LIMIT 10;
