-- {"query": "451.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2680} 
with params as (
    select
        date_trunc('month', now()) - interval '24 months' as start_month,
        date_trunc('month', now()) - interval '1 month'  as end_month
),
months as (
    select generate_series(start_month, end_month, interval '1 month')::date as month_start
    from params
),
questions as (
    select p.Id, p.CreationDate::date as created_date, p.OwnerUserId, p.Score, p.ViewCount, p.Title, p.Tags,
           coalesce(p.AnswerCount, 0) as AnswerCount,
           case when p.ClosedDate is null then 0 else 1 end as IsClosed
    from Posts p
    where p.PostTypeId = 1
),
answers as (
    select a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select a.ParentId as QuestionId,
           min(a.CreationDate) as FirstAnswerDate
    from answers a
    group by a.ParentId
),
dupes as (
    select pl.PostId as QuestionId,
           min(pl.CreationDate) as FirstDuplicateMark
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
tag_expanded as (
    select q.Id as QuestionId,
           unnest(string_to_array(nullif(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), ''><''), '><')) as TagName
    from questions q
),
top_user_badges as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
           count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
user_activity as (
    select u.Id as UserId,
           u.Reputation,
           u.UpVotes,
           u.DownVotes,
           u.Views as ProfileViews,
           coalesce(tub.TotalBadges, 0) as TotalBadges,
           coalesce(tub.GoldCount, 0) as GoldBadges,
           coalesce(tub.SilverCount, 0) as SilverBadges,
           coalesce(tub.BronzeCount, 0) as BronzeBadges
    from Users u
    left join top_user_badges tub on tub.UserId = u.Id
),
question_metrics as (
    select
        q.Id as QuestionId,
        date_trunc('month', q.CreationDate)::date as MonthStart,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.IsClosed,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        extract(epoch from (fa.FirstAnswerDate - q.CreationDate))/60.0 as MinutesToFirstAnswer,
        extract(epoch from (fa.FirstAnswerDate - q.CreationDate))/3600.0 as HoursToFirstAnswer,
        case
            when fa.FirstAnswerDate is null then null
            when fa.FirstAnswerDate <= q.CreationDate then 0
            else 1
        end as FirstAnswerAfterPost,
        case when d.FirstDuplicateMark is null then 0 else 1 end as IsDuplicateMarked,
        d.FirstDuplicateMark
    from Posts q
    left join first_answer fa on fa.QuestionId = q.Id
    left join dupes d on d.QuestionId = q.Id
    where q.PostTypeId = 1
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as Upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as Downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
    from Votes v
    group by v.PostId
),
comments_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as CommentScoreSum,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
per_month as (
    select
        m.month_start,
        count(distinct qm.QuestionId) as Questions,
        count(distinct case when qm.HasAccepted = 1 then qm.QuestionId end) as QuestionsWithAccepted,
        avg(nullif(qm.MinutesToFirstAnswer, 0)) as AvgMinutesToFirstAnswer,
        percentile_cont(0.5) within group (order by qm.HoursToFirstAnswer) as P50HoursToFirstAnswer,
        percentile_cont(0.9) within group (order by qm.HoursToFirstAnswer) as P90HoursToFirstAnswer,
        sum(case when qm.IsDuplicateMarked = 1 then 1 else 0 end) as DuplicatesMarked,
        sum(qm.IsClosed) as ClosedCount
    from months m
    left join question_metrics qm
      on date_trunc('month', qm.MonthStart) = m.month_start
    group by m.month_start
),
user_quality as (
    select
        qa.OwnerUserId as UserId,
        count(*) as QuestionsAuthored,
        avg(coalesce(va.Upvotes,0) - coalesce(va.Downvotes,0)) as AvgNetVotes,
        avg(qm.QuestionScore) as AvgQuestionScore,
        avg(coalesce(va.Favorites,0)) as AvgFavorites,
        sum(case when qm.HasAccepted = 1 then 1 else 0 end) as AcceptedQuestionCount,
        avg(case when qm.FirstAnswerAfterPost = 1 then qm.HoursToFirstAnswer end) as AvgHoursToFirstAnswer,
        sum(case when qm.IsDuplicateMarked = 1 then 1 else 0 end) as DupesOnUserQuestions
    from question_metrics qm
    join Posts qa on qa.Id = qm.QuestionId
    left join votes_agg va on va.PostId = qm.QuestionId
    group by qa.OwnerUserId
),
tag_health as (
    select
        te.TagName,
        count(distinct te.QuestionId) as QuestionsWithTag,
        avg(qm.HoursToFirstAnswer) as AvgHrsToAns,
        sum(case when qm.HasAccepted = 1 then 1 else 0 end) as AcceptedCount,
        sum(case when qm.IsDuplicateMarked = 1 then 1 else 0 end) as Dupes,
        count(distinct case when qm.IsClosed = 1 then te.QuestionId end) as ClosedWithTag,
        percentile_cont(0.5) within group (order by qm.HoursToFirstAnswer) as P50Hrs,
        percentile_cont(0.9) within group (order by qm.HoursToFirstAnswer) as P90Hrs
    from tag_expanded te
    join question_metrics qm on qm.QuestionId = te.QuestionId
    group by te.TagName
),
recent_hot_candidates as (
    select
        qm.QuestionId,
        qm.MonthStart,
        qm.QuestionScore,
        coalesce(va.Upvotes,0) as Upvotes,
        coalesce(va.Downvotes,0) as Downvotes,
        coalesce(va.Favorites,0) as Favorites,
        coalesce(ca.CommentCount,0) as CommentCount,
        rank() over (partition by date_trunc('month', qm.MonthStart) order by (coalesce(va.Upvotes,0) - coalesce(va.Downvotes,0)) desc, qm.ViewCount desc) as rnk
    from question_metrics qm
    left join votes_agg va on va.PostId = qm.QuestionId
    left join comments_agg ca on ca.PostId = qm.QuestionId
    where qm.MonthStart >= (select start_month from params)
),
filtered_questions as (
    select
        qm.QuestionId,
        qm.MonthStart,
        u.DisplayName as OwnerName,
        ua.Reputation,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        qm.QuestionScore,
        coalesce(va.Upvotes,0) as Upvotes,
        coalesce(va.Downvotes,0) as Downvotes,
        coalesce(va.Favorites,0) as Favorites,
        coalesce(ca.CommentCount,0) as CommentCount,
        coalesce(ca.CommentScoreSum,0) as CommentScoreSum,
        qm.ViewCount,
        qm.HasAccepted,
        qm.HoursToFirstAnswer,
        qm.IsDuplicateMarked,
        qm.IsClosed,
        case
            when qm.IsClosed = 1 and qm.HasAccepted = 1 then 'ClosedWithAccepted'
            when qm.IsClosed = 1 and qm.HasAccepted = 0 then 'ClosedNoAccepted'
            when qm.IsClosed = 0 and qm.HasAccepted = 1 then 'OpenWithAccepted'
            else 'OpenNoAccepted'
        end as StatusBucket,
        (coalesce(va.Upvotes,0) - coalesce(va.Downvotes,0)) as NetVotes,
        (case when qm.HoursToFirstAnswer is null then 0 else 1 end) as HasAnswer
    from question_metrics qm
    left join votes_agg va on va.PostId = qm.QuestionId
    left join comments_agg ca on ca.PostId = qm.QuestionId
    left join Users u on u.Id = qm.OwnerUserId
    left join user_activity ua on ua.UserId = qm.OwnerUserId
    where qm.MonthStart between (select start_month from params) and (select end_month from params)
),
ranked_questions as (
    select
        fq.*,
        row_number() over (partition by date_trunc('month', fq.MonthStart) order by fq.NetVotes desc, fq.ViewCount desc, fq.Favorites desc) as rn_net,
        dense_rank() over (order by fq.Reputation desc nulls last) as dr_user_rep,
        ntile(10) over (order by fq.ViewCount) as view_ntile
    from filtered_questions fq
),
unioned as (
    select
        'month_agg' as bucket,
        to_char(pm.month_start, 'YYYY-MM') as period,
        null::int as question_id,
        null::varchar as owner_name,
        null::int as reputation,
        null::int as total_badges,
        null::int as gold_badges,
        null::int as silver_badges,
        null::int as bronze_badges,
        pm.questions as metric1,
        pm.questionswithaccepted as metric2,
        pm.duplicatesmarked as metric3,
        pm.closedcount as metric4,
        pm.avgminutestofirstanswer as metric5,
        pm.p50hourstofirstanswer as metric6,
        pm.p90hourstofirstanswer as metric7,
        null::int as net_votes,
        null::int as upvotes,
        null::int as downvotes,
        null::int as favorites,
        null::int as comment_count,
        null::int as comment_score_sum,
        null::int as view_count,
        null::varchar as status_bucket,
        null::int as view_ntile
    from per_month pm
    union all
    select
        'top_questions' as bucket,
        to_char(rq.MonthStart, 'YYYY-MM') as period,
        rq.QuestionId,
        rq.OwnerName,
        rq.Reputation,
        rq.TotalBadges,
        rq.GoldBadges,
        rq.SilverBadges,
        rq.BronzeBadges,
        rq.QuestionScore as metric1,
        rq.HasAccepted as metric2,
        rq.IsDuplicateMarked as metric3,
        rq.IsClosed as metric4,
        rq.HoursToFirstAnswer as metric5,
        null::numeric as metric6,
        null::numeric as metric7,
        rq.NetVotes,
        rq.Upvotes,
        rq.Downvotes,
        rq.Favorites,
        rq.CommentCount,
        rq.CommentScoreSum,
        rq.ViewCount,
        rq.StatusBucket,
        rq.view_ntile
    from ranked_questions rq
    where rq.rn_net <= 50
)
select *
from unioned
order by bucket, period, coalesce(question_id, 0) desc;