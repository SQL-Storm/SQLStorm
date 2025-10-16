-- {"query": "193.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1459} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt_up.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vt_down.VoteCount),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vt_up on vt_up.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vt_down on vt_down.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as QuestionPostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        row_number() over (partition by t.TagName order by p.Score desc nulls last, p.ViewCount desc nulls last) as TagRank
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    where t.Count > 1000
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswerCount
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionWithAnswers as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        coalesce(as.AnswerCount,0) as AnswerCount,
        coalesce(as.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(as.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(as.AnonymousAnswerCount,0) as AnonymousAnswerCount,
        pcr.CloseReasonName,
        pcr.CloseDate
    from Posts q
    left join AnswerStats as on as.QuestionId = q.Id
    left join PostCloseReasons pcr on pcr.PostId = q.Id
    where q.PostTypeId = 1
),
RankedQuestions as (
    select
        q.*,
        dense_rank() over (partition by q.CloseReasonName order by q.Score desc nulls last, q.ViewCount desc nulls last) as CloseReasonRank
    from QuestionWithAnswers q
),
UserActivityWithBadges as (
    select
        rua.*,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.DistinctBadges,0) as DistinctBadges
    from RecursiveUserActivity rua
    left join UserBadgeSummary ubs on ubs.UserId = rua.UserId
),
UserTopTags as (
    select
        uta.UserId,
        t.TagName,
        count(*) as TagQuestionCount,
        max(p.Score) as MaxScoreForTag,
        sum(p.ViewCount) as TotalViewsForTag
    from Posts p
    join Tags t on p.Tags like concat('%<', t.TagName, '>%')
    join Users uta on p.OwnerUserId = uta.Id
    where p.PostTypeId = 1
    group by uta.UserId, t.TagName
),
UserTopTagRanked as (
    select
        utt.*,
        row_number() over (partition by utt.UserId order by utt.TagQuestionCount desc, utt.TotalViewsForTag desc) as TagRank
    from UserTopTags utt
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.DistinctBadges,
    coalesce(q.CloseReasonName, 'Open') as PostStatus,
    q.Title as TopQuestionTitle,
    q.Score as TopQuestionScore,
    q.ViewCount as TopQuestionViews,
    q.AnswerCount as TopQuestionAnswerCount,
    q.AvgAnswerScore as TopQuestionAvgAnswerScore,
    q.MaxAnswerScore as TopQuestionMaxAnswerScore,
    q.AnonymousAnswerCount as TopQuestionAnonymousAnswers,
    t.TagName as FavoriteTag,
    t.TagQuestionCount,
    t.TotalViewsForTag
from UserActivityWithBadges u
left join LATERAL (
    select q.*
    from RankedQuestions q
    where q.OwnerUserId = u.UserId
    order by q.Score desc nulls last, q.ViewCount desc nulls last
    limit 1
) q on true
left join LATERAL (
    select utt.TagName, utt.TagQuestionCount, utt.TotalViewsForTag
    from UserTopTagRanked utt
    where utt.UserId = u.UserId and utt.TagRank = 1
) t on true
where u.UserRank <= 100
order by u.Reputation desc, u.UserId
;