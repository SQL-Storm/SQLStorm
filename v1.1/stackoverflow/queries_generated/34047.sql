-- {"query": "34047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1147} 

WITH QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(best_answer.Score, 0) AS BestAnswerScore,
        COALESCE(badge_summary.GoldBadges, 0) AS GoldBadges,
        COALESCE(badge_summary.SilverBadges, 0) AS SilverBadges,
        COALESCE(badge_summary.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(comments.CommentCount, 0) AS TotalComments,
        ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS Tags,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5)) AS LastEditDate
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id AND pt.Name = 'Question'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS AnswerCount
        FROM Posts ans
        WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2
    ) a ON true
    LEFT JOIN LATERAL (
        SELECT p2.Score
        FROM Posts p2
        WHERE p2.Id = p.AcceptedAnswerId
    ) best_answer ON true
    LEFT JOIN (
        SELECT UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) badge_summary ON badge_summary.UserId = p.OwnerUserId
    LEFT JOIN (
        SELECT p.Id AS PostId, COUNT(c.Id) AS CommentCount
        FROM Posts p
        LEFT JOIN Comments c ON c.PostId = p.Id
        GROUP BY p.Id
    ) comments ON comments.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON true
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.Id, u.DisplayName, u.Reputation, a.AnswerCount, best_answer.Score, badge_summary.GoldBadges, badge_summary.SilverBadges, badge_summary.BronzeBadges, comments.CommentCount
),
RankedQuestions AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY QuestionScore DESC, AnswerCount DESC, ViewCount DESC) AS RankByScore,
        ROW_NUMBER() OVER (ORDER BY OwnerReputation DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC) AS RankByOwner
    FROM QuestionStats
),
AnswerDetails AS (
    SELECT
        ans.ParentId AS QuestionId,
        ans.Id AS AnswerId,
        ans.Score AS AnswerScore,
        ans.CreationDate AS AnswerCreation,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty
    FROM Posts ans
    LEFT JOIN Users u ON ans.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = ans.Id
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE ans.PostTypeId = 2 -- Answers
    GROUP BY ans.ParentId, ans.Id, ans.Score, ans.CreationDate, u.DisplayName, u.Reputation
),
TopAnswers AS (
    SELECT DISTINCT ON (QuestionId) *
    FROM AnswerDetails
    ORDER BY QuestionId, AnswerScore DESC, AnswerCreation ASC
)
SELECT 
    rq.QuestionId,
    rq.Title AS QuestionTitle,
    rq.CreationDate AS QuestionCreationDate,
    rq.QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.BestAnswerScore,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.TotalComments,
    rq.Tags,
    rq.LastEditDate,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.OwnerReputation,
    ta.AnswerId AS TopAnswerId,
    ta.AnswerScore AS TopAnswerScore,
    ta.AnswerCreation,
    ta.AnswerOwnerName,
    ta.AnswerOwnerReputation,
    ta.UpVotes,
    ta.DownVotes,
    ta.TotalBounty
FROM RankedQuestions rq
LEFT JOIN TopAnswers ta ON ta.QuestionId = rq.QuestionId
WHERE rq.RankByScore <= 50 OR rq.RankByOwner <= 50
ORDER BY rq.RankByScore, rq.RankByOwner;
