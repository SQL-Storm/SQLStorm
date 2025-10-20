-- {"query": "495.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Tags,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostLinkSummary as (
    select 
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinks,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostCommentsAgg as (
    select 
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
RankedUserPosts as (
    select
        rua.UserId,
        rua.PostId,
        rua.PostTypeId,
        rua.PostCreationDate,
        rua.PostScore,
        rua.ViewCount,
        rua.Tags,
        rua.AcceptedAnswerId,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        pls.DuplicateLinks,
        pls.LinkedPosts,
        pca.CommentCount,
        pca.TotalCommentScore,
        pca.LastCommentDate,
        row_number() over (partition by rua.UserId order by rua.PostScore desc, rua.ViewCount desc) as ScoreRank
    from RecursiveUserActivity rua
    left join UserBadgeCounts ubc on ubc.UserId = rua.UserId
    left join PostLinkSummary pls on pls.PostId = rua.PostId
    left join PostCommentsAgg pca on pca.PostId = rua.PostId
    where rua.RecentPostRank <= 50
),
AcceptedAnswerInfo as (
    select 
        p.Id,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags
    from Posts p
    where p.PostTypeId = 2
),
UserAnswerStats as (
    select 
        rup.UserId,
        count(distinct rup.PostId) as AnswerCount,
        avg(rup.PostScore) as AvgAnswerScore,
        sum(case when aa.Score > 10 then 1 else 0 end) as HighScoreAcceptedAnswers,
        max(rup.PostCreationDate) as LastAnswerDate
    from RankedUserPosts rup
    left join AcceptedAnswerInfo aa on aa.Id = rup.PostId and aa.OwnerUserId = rup.UserId
    where rup.PostTypeId = 2
    group by rup.UserId
),
UserQuestionStats as (
    select 
        rup.UserId,
        count(distinct rup.PostId) as QuestionCount,
        avg(rup.PostScore) as AvgQuestionScore,
        sum(case when rup.AcceptedAnswerId > 0 then 1 else 0 end) as QuestionsWithAcceptedAnswer,
        max(rup.PostCreationDate) as LastQuestionDate
    from RankedUserPosts rup
    where rup.PostTypeId = 1
    group by rup.UserId
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        coalesce(ua.AnswerCount,0) as AnswerCount,
        coalesce(ua.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ua.HighScoreAcceptedAnswers,0) as HighScoreAcceptedAnswers,
        coalesce(ua.LastAnswerDate, timestamp '1970-01-01') as LastAnswerDate,
        coalesce(uq.QuestionCount,0) as QuestionCount,
        coalesce(uq.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(uq.QuestionsWithAcceptedAnswer,0) as QuestionsWithAcceptedAnswer,
        coalesce(uq.LastQuestionDate, timestamp '1970-01-01') as LastQuestionDate
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join UserAnswerStats ua on ua.UserId = u.Id
    left join UserQuestionStats uq on uq.UserId = u.Id
    where u.Reputation > 1000
),
UserRecentActivity as (
    select 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.AnswerCount,
        uas.AvgAnswerScore,
        uas.HighScoreAcceptedAnswers,
        uas.LastAnswerDate,
        uas.QuestionCount,
        uas.AvgQuestionScore,
        uas.QuestionsWithAcceptedAnswer,
        uas.LastQuestionDate,
        ph.PostHistoryTypeId,
        pht.Name as PostHistoryTypeName,
        ph.CreationDate as HistoryDate,
        ph.Comment as HistoryComment,
        ph.Text as HistoryText,
        row_number() over (partition by uas.UserId order by ph.CreationDate desc) as HistoryRank
    from UserActivitySummary uas
    left join PostHistory ph on ph.UserId = uas.UserId
    left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where ph.CreationDate is not null
)
select 
    ura.UserId,
    ura.DisplayName,
    ura.Reputation,
    ura.GoldBadges,
    ura.SilverBadges,
    ura.BronzeBadges,
    ura.AnswerCount,
    ura.AvgAnswerScore,
    ura.HighScoreAcceptedAnswers,
    ura.LastAnswerDate,
    ura.QuestionCount,
    ura.AvgQuestionScore,
    ura.QuestionsWithAcceptedAnswer,
    ura.LastQuestionDate,
    ura.PostHistoryTypeId,
    ura.PostHistoryTypeName,
    ura.HistoryDate,
    ura.HistoryComment,
    substr(coalesce(ura.HistoryText, ''), 1, 100) as HistoryTextSnippet,
    case 
        when ura.PostHistoryTypeId in (10,12,14) then 'Moderation'
        when ura.PostHistoryTypeId in (1,2,3,4,5,6) then 'ContentEdit'
        else 'Other'
    end as HistoryCategory
from UserRecentActivity ura
where ura.HistoryRank <= 5
order by ura.Reputation desc, ura.UserId, ura.HistoryDate desc;