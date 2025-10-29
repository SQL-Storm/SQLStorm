-- {"query": "2273.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1675}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE AND t.Count > 100

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id = r.Id
    WHERE r.Level < 1
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreated,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        COALESCE(q.AnswerCount, 0) AS NumberOfAnswers,
        COALESCE(a.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        q.Tags,
        q.ClosedDate,
        q.FavoriteCount,
        q.ViewCount
    FROM Posts q
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) AS AnswerCount,
            AVG(Score) AS AvgAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
PostWithVotes AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        p.ViewCount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Title, p.Tags, p.AcceptedAnswerId, p.ViewCount
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        cr.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS integer) AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        LAG(u.Reputation) OVER (ORDER BY u.CreationDate) AS PrevUserReputation,
        LEAD(u.Reputation) OVER (ORDER BY u.CreationDate) AS NextUserReputation,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
DuplicatedPosts AS (
    SELECT DISTINCT p.Id AS PostId, pl.RelatedPostId, pl.LinkTypeId
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
),
HighlyActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionsCount,
        AnswersCount,
        CommentsCount,
        TotalUpVotesReceived,
        COALESCE(PrevUserReputation, 0) AS PrevReputation,
        COALESCE(NextUserReputation, 0) AS NextReputation,
        GREATEST(QuestionsCount, 0) + GREATEST(AnswersCount, 0) * 2 + GREATEST(CommentsCount, 0) * 1 AS ActivityScore
    FROM UserActivityWindow
    WHERE QuestionsCount > 5 OR AnswersCount > 10 OR CommentsCount > 20
)
SELECT 
    pas.QuestionId,
    pas.Title AS QuestionTitle,
    COALESCE(pws.UpVotes, 0) AS QuestionUpVotes,
    COALESCE(pws.DownVotes, 0) AS QuestionDownVotes,
    pas.NumberOfAnswers,
    pas.ActualAnswerCount,
    ROUND(CAST(pas.AvgAnswerScore AS numeric), 2) AS AverageAnswerScore,
    COALESCE(uc.CloseReasonName, 'Open') AS CloseStatus,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ha.DisplayName AS ActiveUserDisplayName,
    ha.ActivityScore,
    ha.TotalUpVotesReceived,
    STRING_AGG(DISTINCT REPLACE(SPLIT_PART(pas.Tags, '><', gs.n), '>', ''), ', ') FILTER (WHERE pas.Tags IS NOT NULL) AS SampleTags,
    ROW_NUMBER() OVER (PARTITION BY pas.NumberOfAnswers ORDER BY pas.QuestionScore DESC, pas.FavoriteCount DESC) AS RankByAnswers,
    CASE 
        WHEN pas.ClosedDate IS NOT NULL AND uc.CloseReasonName IS NOT NULL THEN 'Closed: ' || uc.CloseReasonName
        WHEN pas.ClosedDate IS NOT NULL THEN 'Closed: Unknown Reason'
        ELSE 'Open'
    END AS StatusDescription,
    CASE 
        WHEN pws.ScoreRank <= 10 THEN 'Top 10'
        WHEN pws.ScoreRank <= 100 THEN 'Top 100'
        ELSE 'Others'
    END AS ScoreBracket
FROM PostAnswerStats pas
LEFT JOIN PostWithVotes pws ON pws.PostId = pas.QuestionId
LEFT JOIN PostCloseInfo uc ON uc.PostId = pas.QuestionId AND uc.rn = 1
LEFT JOIN Users u ON u.Id = pas.OwnerUserId
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
LEFT JOIN HighlyActiveUsers ha ON ha.UserId = pas.OwnerUserId
LEFT JOIN generate_series(1,5) gs(n) ON gs.n <= COALESCE(array_length(string_to_array(pas.Tags, '><'), 1), 0)
WHERE pas.NumberOfAnswers > 5
  AND (pws.ScoreRank <= 100 OR pws.ScoreRank IS NULL)
GROUP BY
    pas.QuestionId,
    pas.Title,
    pws.UpVotes,
    pws.DownVotes,
    pas.NumberOfAnswers,
    pas.ActualAnswerCount,
    pas.AvgAnswerScore,
    uc.CloseReasonName,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ha.DisplayName,
    ha.ActivityScore,
    ha.TotalUpVotesReceived,
    pas.QuestionScore,
    pas.FavoriteCount,
    pws.ScoreRank,
    pws.Score,
    pas.ClosedDate,
    pas.Tags
ORDER BY pas.NumberOfAnswers DESC, pws.Score DESC, pas.FavoriteCount DESC
LIMIT 50;