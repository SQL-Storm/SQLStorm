-- {"query": "2734.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1335} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        coalesce(p.Score,0) as PostScore,
        p.OwnerUserId,
        row_number() over (partition by t.TagName order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
),
TopTagQuestions as (
    select
        Id,
        TagName,
        AnswerCount,
        FavoriteCount,
        PostScore,
        OwnerUserId
    from RecursiveTagCounts
    where rn <= 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswers as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerUserId,
        a.CreationDate as AnswerCreation,
        q.OwnerUserId as QuestionOwnerUserId,
        q.Score as QuestionScore,
        q.FavoriteCount as QuestionFavoriteCount,
        q.Tags as QuestionTags
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
AnswerRanked as (
    select
        *,
        rank() over (partition by QuestionId order by AnswerScore desc nulls last, AnswerCreation asc nulls last) as AnswerRank
    from QuestionAnswers
),
AnswersBest as (
    select
        QuestionId, AnswerId, AnswerScore, AnswerUserId
    from AnswerRanked
    where AnswerRank = 1
),
CloseVotesSummary as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        max(p.CreationDate) as LastPostDate,
        avg(extract(epoch from (current_timestamp - p.CreationDate))/3600) as AvgHoursSincePost,
        row_number() over (order by u.Reputation desc nulls last) as UserRankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
UserCommentStats as (
    select
        u.Id as UserId,
        count(c.Id) as TotalComments,
        sum(c.Score) filter (where c.Score is not null) as CommentScoreSum,
        count(distinct c.PostId) as UniquePostsCommentedOn
    from Users u
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select
    ttq.TagName,
    ttq.AnswerCount,
    ttq.FavoriteCount,
    ttq.PostScore,
    ua.DisplayName as OwnerDisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    qas.CloseVotesCount,
    qas.ReopenVotesCount,
    crt.Name as CloseReasonName,
    ab.AnswerId as TopAnswerId,
    ab.AnswerScore as TopAnswerScore,
    uac.DisplayName as TopAnswerUser,
    uac.UserRankByReputation,
    uac.Reputation as TopAnswerUserReputation,
    coalesce(ucs.TotalComments,0) as TopAnswerUserComments,
    coalesce(ucs.CommentScoreSum,0) as TopAnswerUserCommentScores,
    coalesce(ucs.UniquePostsCommentedOn,0) as TopAnswerUserUniquePostsCommented,
    case
        when ub.GoldBadges > 5 and ttq.FavoriteCount > 10 then 'HighImpact'
        when ub.GoldBadges between 1 and 5 then 'MediumImpact'
        else 'LowImpact'
    end as ImpactCategory,
    length(coalesce(p.Title, '')) as TitleLength,
    substring(p.Title from 1 for 15) as TitleSnippet,
    length(coalesce(p.Body, '')) as BodyLength,
    p.CreationDate,
    dense_rank() over (order by ttq.FavoriteCount desc nulls last) as FavoriteRank
from TopTagQuestions ttq
left join Users ua on ua.Id = ttq.OwnerUserId
left join UserBadgeStats ub on ub.UserId = ttq.OwnerUserId
left join Posts p on p.Id = ttq.Id
left join CloseVotesSummary qas on qas.PostId = ttq.Id
left join CloseReasonTypes crt on crt.Id = qas.CloseReasonId
left join AnswersBest ab on ab.QuestionId = ttq.Id
left join Users uac on uac.Id = ab.AnswerUserId
left join UserActivityWindow uaw on uaw.UserId = ua.Id
left join UserCommentStats ucs on ucs.UserId = ab.AnswerUserId
where ttq.AnswerCount > 0
order by ttq.FavoriteCount desc nulls last, ttq.PostScore desc nulls last
limit 20;