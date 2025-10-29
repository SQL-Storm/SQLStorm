-- {"query": "376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2252} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        extract(year from p.CreationDate) as Year,
        extract(month from p.CreationDate) as Month
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(nullif(trim(u.WebsiteUrl), ''), 'n/a') as WebsiteUrlNorm
    from Users u
),
question_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as Upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as Downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
    from Votes v
    join recent_questions q on q.QuestionId = v.PostId
    group by v.PostId
),
first_answer as (
    select distinct on (a.QuestionId)
        a.QuestionId,
        a.AnswerId,
        a.AnswerOwnerId,
        a.AnswerScore,
        a.AnswerCreationDate
    from answers a
    join recent_questions q on q.QuestionId = a.QuestionId
    order by a.QuestionId, a.AnswerCreationDate
),
tag_splits as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(coalesce(q.Tags, ''), 2, greatest(length(coalesce(q.Tags, '')) - 2, 0)), '><')) as TagName
    from recent_questions q
),
tag_metrics as (
    select
        t.TagName,
        count(distinct ts.QuestionId) as QuestionsWithTag,
        sum(q.Score) as SumQuestionScoreWithTag
    from tag_splits ts
    join recent_questions q on q.QuestionId = ts.QuestionId
    join Tags t on lower(t.TagName) = lower(ts.TagName)
    group by t.TagName
),
edits_cte as (
    select
        ph.PostId as QuestionId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as FirstEditDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditDate,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseEvents,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId
    from PostHistory ph
    join recent_questions q on q.QuestionId = ph.PostId
    group by ph.PostId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateRefs,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedRefs
    from PostLinks pl
    join recent_questions q on q.QuestionId = pl.PostId
    group by pl.PostId
),
owner_badges as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) filter (where b.TagBased = 1) as TagBadges
    from Badges b
    group by b.UserId
),
ranked_questions as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(qv.Upvotes, 0) as Upvotes,
        coalesce(qv.Downvotes, 0) as Downvotes,
        coalesce(qv.Favorites, 0) as Favorites,
        coalesce(e.EditEvents, 0) as EditEvents,
        e.FirstEditDate,
        e.LastEditDate,
        coalesce(dl.DuplicateRefs, 0) as DuplicateRefs,
        coalesce(dl.LinkedRefs, 0) as LinkedRefs,
        q.AnswerCount,
        fa.AnswerId as FirstAnswerId,
        fa.AnswerOwnerId,
        fa.AnswerScore as FirstAnswerScore,
        fa.AnswerCreationDate,
        ua.Reputation as OwnerReputation,
        ua.UpVotes as OwnerUpVotes,
        ua.DownVotes as OwnerDownVotes,
        ob.TotalBadges,
        ob.GoldBadges,
        ob.SilverBadges,
        ob.BronzeBadges,
        ob.TagBadges,
        ntile(4) over (order by q.ViewCount nulls last) as ViewQuartile,
        dense_rank() over (order by q.Score desc nulls last) as ScoreRank,
        row_number() over (partition by extract(month from q.CreationDate) order by q.Score desc, q.ViewCount desc) as MonthTopRow
    from recent_questions q
    left join question_votes qv on qv.QuestionId = q.QuestionId
    left join edits_cte e on e.QuestionId = q.QuestionId
    left join duplicate_links dl on dl.QuestionId = q.QuestionId
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join user_activity ua on ua.UserId = q.OwnerUserId
    left join owner_badges ob on ob.UserId = q.OwnerUserId
),
agg_by_month as (
    select
        extract(year from CreationDate) as y,
        extract(month from CreationDate) as m,
        count(*) as q_count,
        avg(Score) as avg_score,
        percentile_disc(0.5) within group (order by Score) as median_score,
        avg(ViewCount) as avg_views,
        avg(EditEvents) as avg_edits
    from ranked_questions
    group by 1,2
),
high_engagement as (
    select
        rq.QuestionId,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.Upvotes,
        rq.Downvotes,
        rq.Favorites,
        rq.AnswerCount,
        rq.EditEvents,
        rq.DuplicateRefs,
        rq.OwnerReputation,
        rq.TotalBadges,
        rq.ViewQuartile,
        rq.ScoreRank,
        rq.MonthTopRow,
        (coalesce(rq.Upvotes,0) - coalesce(rq.Downvotes,0))::numeric / nullif(rq.ViewCount,0) as vote_view_ratio,
        case
            when rq.AnswerCount = 0 then null
            else extract(epoch from (rq.FirstAnswerCreationDate - rq.CreationDate)) / 3600.0
        end as hours_to_first_answer
    from ranked_questions rq
),
closed_reason_map as (
    select
        e.QuestionId,
        case e.LastCloseReasonId
            when 101 then 'Duplicate'
            when 102 then 'Off-topic'
            when 103 then 'Needs details or clarity'
            when 104 then 'Needs more focus'
            when 105 then 'Opinion-based'
            else 'Other/None'
        end as CloseReasonName
    from edits_cte e
)
select
    rq.QuestionId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.Upvotes,
    rq.Downvotes,
    rq.Favorites,
    rq.AnswerCount,
    rq.EditEvents,
    rq.DuplicateRefs,
    rq.LinkedRefs,
    rq.OwnerReputation,
    rq.TotalBadges,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.ViewQuartile,
    rq.ScoreRank,
    rq.MonthTopRow,
    coalesce(h.vote_view_ratio, 0) as vote_view_ratio,
    h.hours_to_first_answer,
    crm.CloseReasonName,
    coalesce(tm_sum.SumQuestionScoreWithTag, 0) as SumScorePrimaryTag,
    abm.avg_score as MonthAvgScore,
    abm.avg_views as MonthAvgViews,
    abm.avg_edits as MonthAvgEdits
from ranked_questions rq
left join high_engagement h on h.QuestionId = rq.QuestionId
left join closed_reason_map crm on crm.QuestionId = rq.QuestionId
left join lateral (
    select tm.TagName, tm.SumQuestionScoreWithTag
    from tag_splits ts
    join tag_metrics tm on tm.TagName = ts.TagName
    where ts.QuestionId = rq.QuestionId
    order by tm.QuestionsWithTag desc, tm.SumQuestionScoreWithTag desc, tm.TagName
    limit 1
) tm_sum on true
left join agg_by_month abm
  on abm.y = extract(year from rq.CreationDate)
 and abm.m = extract(month from rq.CreationDate)
where coalesce(h.vote_view_ratio, 0) >= (
    select avg(coalesce(vote_view_ratio, 0)) + stddev_pop(coalesce(vote_view_ratio, 0))
    from high_engagement
)
and (
    rq.EditEvents > 0
    or rq.DuplicateRefs > 0
    or rq.Favorites >= 1
)
order by
    rq.Score desc nulls last,
    rq.ViewCount desc nulls last,
    rq.QuestionId
limit 500;