-- {"query": "2273.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1675} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        1 as Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.Count > 100

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id = r.Id -- Recursive self join to simulate some recursion (no natural hierarchy here)
    WHERE r.Level < 1
),
UserBadgeStats AS (
    SELECT
        u.Id as UserId,
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
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        q.OwnerUserId,
        q.Score as QuestionScore,
        COALESCE(q.AnswerCount,0) as NumberOfAnswers,
        COALESCE(a.AnswerCount,0) as ActualAnswerCount,
        COALESCE(a.AvgAnswerScore, 0) as AvgAnswerScore,
        q.Tags,
        q.ClosedDate,
        q.FavoriteCount,
        q.ViewCount
    FROM Posts q
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) as AnswerCount,
            AVG(Score) as AvgAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
PostWithVotes AS (
    SELECT
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) as ScoreRank
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Title, p.Tags, p.AcceptedAnswerId
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        cr.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS int) AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
),
UserActivityWindow AS (
    SELECT
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=2) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        SUM(v.VoteTypeId = 2)::int AS TotalUpVotesReceived,
        LAG(u.Reputation) OVER (ORDER BY u.CreationDate) AS PrevUserReputation,
        LEAD(u.Reputation) OVER (ORDER BY u.CreationDate) AS NextUserReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
DuplicatedPosts AS (
    SELECT DISTINCT p.Id as PostId, pl.RelatedPostId, pl.LinkTypeId
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3 -- duplicates
),
HighlyActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionsCount,
        AnswersCount,
        CommentsCount,
        TotalUpVotesReceived,
        COALESCE(PrevUserReputation,0) as PrevReputation,
        COALESCE(NextUserReputation,0) as NextReputation,
        GREATEST(QuestionsCount,0) + GREATEST(AnswersCount,0)*2 + GREATEST(CommentsCount,0)*1 as ActivityScore
    FROM UserActivityWindow
    WHERE QuestionsCount > 5 OR AnswersCount > 10 OR CommentsCount > 20
)
SELECT 
    pas.QuestionId,
    pas.Title as QuestionTitle,
    COALESCE(pws.UpVotes,0) as QuestionUpVotes,
    COALESCE(pws.DownVotes,0) as QuestionDownVotes,
    pas.NumberOfAnswers,
    pas.ActualAnswerCount,
    ROUND(pas.AvgAnswerScore::numeric,2) as AverageAnswerScore,
    COALESCE(uc.CloseReasonName, 'Open') as CloseStatus,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ha.DisplayName as ActiveUserDisplayName,
    ha.ActivityScore,
    ha.TotalUpVotesReceived,
    STRING_AGG(DISTINCT REPLACE(SPLIT_PART(pas.Tags, '><', gs.n), '>', '') , ', ') FILTER (WHERE pas.Tags IS NOT NULL) as SampleTags,
    ROW_NUMBER() OVER (PARTITION BY pas.NumberOfAnswers ORDER BY pas.Score DESC NULLS LAST, pas.FavoriteCount DESC NULLS LAST) as RankByAnswers,
    CASE 
        WHEN pas.ClosedDate IS NOT NULL AND uc.CloseReasonName IS NOT NULL THEN CONCAT('Closed: ', uc.CloseReasonName)
        WHEN pas.ClosedDate IS NOT NULL THEN 'Closed: Unknown Reason'
        ELSE 'Open'
    END as StatusDescription,
    CASE 
        WHEN pws.ScoreRank <= 10 THEN 'Top 10'
        WHEN pws.ScoreRank <= 100 THEN 'Top 100'
        ELSE 'Others'
    END as ScoreBracket
FROM PostAnswerStats pas
LEFT JOIN PostWithVotes pws ON pws.PostId = pas.QuestionId
LEFT JOIN PostCloseInfo uc ON uc.PostId = pas.QuestionId AND uc.rn = 1
LEFT JOIN Users u ON u.Id = pas.OwnerUserId
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
LEFT JOIN HighlyActiveUsers ha ON ha.UserId = pas.OwnerUserId
LEFT JOIN generate_series(1,5) gs(n) ON gs.n <= array_length(string_to_array(pas.Tags, '><'), 1) -- rough parsing of tags for strings aggregation
WHERE pas.NumberOfAnswers > 5
  AND (pws.ScoreRank <= 100 OR pws.ScoreRank IS NULL)
ORDER BY pas.NumberOfAnswers DESC, pws.Score DESC NULLS LAST, pas.FavoriteCount DESC NULLS LAST
LIMIT 50;
