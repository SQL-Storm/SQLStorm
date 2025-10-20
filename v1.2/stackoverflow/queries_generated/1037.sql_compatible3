with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges,
        coalesce(u.Reputation,0) as Reputation
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestions as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
),
QuestionsWithAcceptedAnswers_fixed as (
    select
        q.QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.CreationDate,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerUserId
    from TopQuestions q
    left join lateral (
        select p2.Id, p2.Score, p2.OwnerUserId
        from Posts p2
        where p2.Id = (select p3.AcceptedAnswerId from Posts p3 where p3.Id = q.QuestionId)
    ) a on true
),
TagExploded as (
    select
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as TagName
    from TopQuestions q
    where q.rn <= 20
),
TagStats as (
    select
        t.TagName,
        count(distinct t.QuestionId) as QuestionCount,
        avg(t.Score) as AvgQuestionScore,
        avg(t.ViewCount) as AvgViewCount
    from TagExploded t
    group by t.TagName
    having count(distinct t.QuestionId) > 10
),
UserActivityWindow as (
    select
        vhq.OwnerUserId,
        vhq.QuestionId,
        vhq.Score,
        vhq.ViewCount,
        vhq.CreationDate,
        count(*) over (partition by vhq.OwnerUserId order by vhq.CreationDate rows between 30 preceding and current row) as QuestionsLast30Days,
        avg(vhq.Score) over (partition by vhq.OwnerUserId order by vhq.CreationDate rows between 30 preceding and current row) as AvgScoreLast30Days
    from TopQuestions vhq
),
UserCloseReasons as (
    select
        ph.UserId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    where ph.UserId is not null
    group by ph.UserId, crt.Name
),
UserQuestionStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalQuestions,
        coalesce(sum(p.Score),0) as TotalScore,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        count(case when p.ClosedDate is not null then 1 end) as ClosedQuestions,
        count(case when p.AcceptedAnswerId is not null then 1 end) as QuestionsWithAcceptedAnswer
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    group by u.Id, u.DisplayName
),
CombinedUserStats as (
    select
        ubc.UserId,
        ubc.DisplayName,
        ubc.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        uqs.TotalQuestions,
        uqs.TotalScore,
        uqs.AvgScore,
        uqs.MaxScore,
        uqs.ClosedQuestions,
        uqs.QuestionsWithAcceptedAnswer,
        coalesce(sum(ucr.CloseVotesCount),0) as CloseVotesCast,
        coalesce(string_agg(distinct ucr.CloseReason, ', '), '') as CloseReasonsUsed
    from UserBadgeCounts ubc
    left join UserQuestionStats uqs on uqs.UserId = ubc.UserId
    left join UserCloseReasons ucr on ucr.UserId = ubc.UserId
    group by ubc.UserId, ubc.DisplayName, ubc.Reputation, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges, uqs.TotalQuestions, uqs.TotalScore, uqs.AvgScore, uqs.MaxScore, uqs.ClosedQuestions, uqs.QuestionsWithAcceptedAnswer
)
select 
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.TotalBadges,
    cast(ucs.GoldBadges as varchar) as GoldBadges,
    cast(ucs.SilverBadges as varchar) as SilverBadges,
    cast(ucs.BronzeBadges as varchar) as BronzeBadges,
    ucs.TotalQuestions,
    ucs.TotalScore,
    round(cast(ucs.AvgScore as numeric), 2) as AvgScore,
    ucs.MaxScore,
    ucs.ClosedQuestions,
    ucs.QuestionsWithAcceptedAnswer,
    ucs.CloseVotesCast,
    ucs.CloseReasonsUsed,
    ts.TagName as PopularTag,
    ts.QuestionCount as PopularTagQuestionCount,
    round(cast(ts.AvgQuestionScore as numeric),2) as PopularTagAvgScore,
    round(cast(ts.AvgViewCount as numeric),2) as PopularTagAvgViews
from CombinedUserStats ucs
left join lateral (
    select
        t.TagName,
        t.QuestionCount,
        t.AvgQuestionScore,
        t.AvgViewCount
    from TagStats t
    join TagExploded te on te.TagName = t.TagName
    join TopQuestions tq on tq.QuestionId = te.QuestionId and tq.OwnerUserId = ucs.UserId
    order by t.QuestionCount desc, t.AvgQuestionScore desc
    limit 1
) ts on true
where ucs.TotalQuestions > 10 and ucs.Reputation > 1000
order by ucs.Reputation desc, ucs.TotalBadges desc
limit 50;