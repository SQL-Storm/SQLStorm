WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(p.Score) as AvgPostScore,
        SUM(p.ViewCount) as TotalViews,
        COUNT(DISTINCT b.Name) as UniqueBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagExperts AS (
    SELECT 
        t.TagName,
        u.Id as UserId,
        COUNT(DISTINCT p.Id) as TagPostCount,
        SUM(p.Score) as TagScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 0
    GROUP BY t.TagName, u.Id
    HAVING COUNT(DISTINCT p.Id) >= 10
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as EditCount,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        MAX(ph.CreationDate) - MIN(p.CreationDate) as EditTimeSpan
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (2,4,5,6,8)
    GROUP BY ph.PostId
),
QuestionQuality AS (
    SELECT 
        q.Id,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(a.Score, 0) as AcceptedAnswerScore,
        COALESCE(eh.EditCount, 0) as EditCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(ans.Score) as AvgAnswerScore,
        MAX(ans.Score) as MaxAnswerScore,
        COUNT(DISTINCT pl.Id) as LinkedPostCount,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Posts ans ON q.Id = ans.ParentId AND ans.PostTypeId = 2
    LEFT JOIN EditHistory eh ON q.Id = eh.PostId
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId OR q.Id = pl.RelatedPostId
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2 years'
      AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, 
             q.FavoriteCount, a.Score, eh.EditCount, q.ClosedDate
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as Bounties,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyAmount,
        COUNT(DISTINCT v.UserId) as UniqueVoters,
        COUNT(DISTINCT DATE(v.CreationDate)) as VotingDays
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY v.PostId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.QuestionCount,
    um.AnswerCount,
    um.AvgPostScore,
    um.GoldBadges,
    um.SilverBadges,
    COUNT(DISTINCT te.TagName) as ExpertTagCount,
    STRING_AGG(DISTINCT CASE WHEN te.TagRank = 1 THEN te.TagName END, ', ') as TopExpertTags,
    COUNT(DISTINCT qq.Id) as HighQualityQuestions,
    AVG(qq.ViewCount) as AvgQuestionViews,
    AVG(qq.AvgAnswerScore) as AvgAnswerScoreReceived,
    SUM(vp.UpVotes) as TotalUpVotesReceived,
    SUM(vp.TotalBountyAmount) as TotalBountiesReceived,
    AVG(CASE WHEN qq.IsClosed = 0 THEN qq.AnswerCount END) as AvgAnswersPerOpenQuestion,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qq.QuestionScore) as MedianQuestionScore,
    MAX(qq.MaxAnswerScore) as BestAnswerScore
FROM UserMetrics um
LEFT JOIN TagExperts te ON um.Id = te.UserId AND te.TagRank <= 3
LEFT JOIN QuestionQuality qq ON um.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qq.Id)
LEFT JOIN VotePatterns vp ON qq.Id = vp.PostId
WHERE um.PostCount >= 50
  AND um.Reputation >= 5000
GROUP BY um.Id, um.DisplayName, um.Reputation, um.QuestionCount, 
         um.AnswerCount, um.AvgPostScore, um.GoldBadges, um.SilverBadges
HAVING COUNT(DISTINCT te.TagName) >= 3
ORDER BY um.Reputation DESC, SUM(vp.TotalBountyAmount) DESC
LIMIT 100;