-- {"query": "72.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2956}
with params as (
    select
        date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '24 months' as start_month,
        date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) as end_month
),
months as (
    select generate_series(p.start_month, p.end_month, interval '1 month') as month_start
    from params p
),
questions as (
    select
        q.Id,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.Title,
        q.AcceptedAnswerId,
        date_trunc('month', q.CreationDate) as month_start
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select start_month from params)
      and q.CreationDate < (select end_month from params) + interval '1 month'
),
answers as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        date_trunc('month', a.CreationDate) as month_start
    from Posts a
    where a.PostTypeId = 2
      and a.CreationDate >= (select start_month from params)
      and a.CreationDate < (select end_month from params) + interval '1 month'
),
accepted_answers as (
    select a.*
    from answers a
    join questions q on q.AcceptedAnswerId = a.Id
),
comment_counts as (
    select c.PostId, count(*) as comment_count, sum(c.Score) as comment_score_sum
    from Comments c
    where c.CreationDate >= (select start_month from params)
      and c.CreationDate < (select end_month from params) + interval '1 month'
    group by c.PostId
),
vote_aggs as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_total
    from Votes v
    group by v.PostId
),
tag_expanded as (
    select
        q.Id as QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag,
        q.month_start
    from questions q
    where q.Tags is not null
      and q.Tags like '<%>'
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.DisplayName,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        (u.UpVotes - u.DownVotes) as net_votes,
        width_bucket(u.Reputation, 0, 100000, 10) as rep_bucket
    from Users u
),
badge_counts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as gold,
        sum(case when b.Class = 2 then 1 else 0 end) as silver,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze,
        sum(case when b.TagBased = true then 1 else 0 end) as tag_badges
    from Badges b
    group by b.UserId
),
post_history_flags as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as ever_closed,
        max(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ever_reopened,
        max(case when ph.PostHistoryTypeId in (12,10) then 1 else 0 end) as ever_moderated,
        max(case when ph.PostHistoryTypeId = 50 then 1 else 0 end) as community_bump
    from PostHistory ph
    group by ph.PostId
),
dup_links as (
    select pl.PostId, count(*) as duplicate_link_count
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
question_quality as (
    select
        q.Id as QuestionId,
        q.month_start,
        q.Score,
        q.ViewCount,
        coalesce(vc.upvotes,0) as upvotes,
        coalesce(vc.downvotes,0) as downvotes,
        coalesce(vc.favorites,0) as favorites,
        coalesce(vc.bounty_total,0) as bounty_total,
        coalesce(cc.comment_count,0) as comment_count,
        coalesce(cc.comment_score_sum,0) as comment_score_sum,
        coalesce(d.duplicate_link_count,0) as duplicate_link_count,
        coalesce(ph.ever_closed,0) as ever_closed,
        coalesce(ph.ever_reopened,0) as ever_reopened,
        coalesce(ph.community_bump,0) as community_bump,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as has_accepted_answer,
        case when lower(q.Title) like '%how to%' or lower(q.Title) like 'how do i %' then 1 else 0 end as howto_flag,
        nullif(length(coalesce(q.Title,'')),0) as title_len,
        nullif(length(regexp_replace(coalesce(q.Title,''), '<[^>]+>', '', 'g')),0) as body_text_len
    from questions q
    left join vote_aggs vc on vc.PostId = q.Id
    left join comment_counts cc on cc.PostId = q.Id
    left join post_history_flags ph on ph.PostId = q.Id
    left join dup_links d on d.PostId = q.Id
),
answer_aggs as (
    select
        a.QuestionId,
        count(*) as answer_count,
        sum(case when a.Score > 0 then 1 else 0 end) as positive_answers,
        max(a.Score) as max_answer_score,
        avg(a.Score) as avg_answer_score,
        min(a.CreationDate) filter (where a.Score >= 0) as first_nonneg_answer_time
    from answers a
    group by a.QuestionId
),
accepted_answer_lag as (
    select
        q.Id as QuestionId,
        extract(epoch from (acc.CreationDate - q.CreationDate)) / 3600.0 as hours_to_accept
    from questions q
    join accepted_answers acc on acc.QuestionId = q.Id
),
monthly_tag_stats as (
    select
        t.month_start,
        t.tag,
        count(distinct t.QuestionId) as questions_with_tag
    from tag_expanded t
    group by t.month_start, t.tag
),
question_user as (
    select
        q.Id as QuestionId,
        u.UserId,
        u.Reputation,
        u.Location,
        u.rep_bucket,
        coalesce(b.gold,0) as gold,
        coalesce(b.silver,0) as silver,
        coalesce(b.bronze,0) as bronze,
        coalesce(b.tag_badges,0) as tag_badges
    from questions q
    left join user_activity u on u.UserId = q.OwnerUserId
    left join badge_counts b on b.UserId = q.OwnerUserId
),
monthly_rollup as (
    select
        m.month_start,
        count(distinct q.Id) as questions,
        sum(qq.has_accepted_answer) as with_accepted,
        avg(nullif(qq.ViewCount,0)) as avg_views,
        percentile_disc(0.5) within group (order by coalesce(qq.Score,0)) as median_score,
        sum(qq.upvotes) as upvotes,
        sum(qq.downvotes) as downvotes,
        sum(qq.favorites) as favorites,
        sum(qq.bounty_total) as bounty_total,
        sum(qq.comment_count) as comments,
        sum(qq.duplicate_link_count) as dup_links
    from months m
    left join questions q on q.month_start = m.month_start
    left join question_quality qq on qq.QuestionId = q.Id
    group by m.month_start
),
per_question_features as (
    select
        q.Id as QuestionId,
        q.month_start,
        qq.Score,
        qq.ViewCount,
        qq.upvotes,
        qq.downvotes,
        qq.favorites,
        qq.bounty_total,
        qq.comment_count,
        qq.comment_score_sum,
        qq.duplicate_link_count,
        qq.ever_closed,
        qq.ever_reopened,
        qq.community_bump,
        qq.has_accepted_answer,
        qq.howto_flag,
        qq.title_len,
        qq.body_text_len,
        coalesce(aa.answer_count,0) as answer_count,
        coalesce(aa.positive_answers,0) as positive_answers,
        coalesce(aa.max_answer_score,0) as max_answer_score,
        coalesce(aa.avg_answer_score,0.0) as avg_answer_score,
        aal.hours_to_accept,
        qu.Reputation as owner_rep,
        qu.rep_bucket,
        qu.gold, qu.silver, qu.bronze, qu.tag_badges,
        case when lower(coalesce(qu.Location,'')) like '%remote%' then 1 else 0 end as loc_remote_flag
    from questions q
    left join question_quality qq on qq.QuestionId = q.Id
    left join answer_aggs aa on aa.QuestionId = q.Id
    left join accepted_answer_lag aal on aal.QuestionId = q.Id
    left join question_user qu on qu.QuestionId = q.Id
),
ranked_questions as (
    select
        pq.QuestionId,
        pq.month_start,
        pq.Score,
        pq.ViewCount,
        pq.upvotes,
        pq.downvotes,
        pq.favorites,
        pq.bounty_total,
        pq.comment_count,
        pq.comment_score_sum,
        pq.duplicate_link_count,
        pq.ever_closed,
        pq.ever_reopened,
        pq.community_bump,
        pq.has_accepted_answer,
        pq.howto_flag,
        pq.title_len,
        pq.body_text_len,
        pq.answer_count,
        pq.positive_answers,
        pq.max_answer_score,
        pq.avg_answer_score,
        pq.hours_to_accept,
        pq.owner_rep,
        pq.rep_bucket,
        pq.gold,
        pq.silver,
        pq.bronze,
        pq.tag_badges,
        pq.loc_remote_flag,
        row_number() over (partition by pq.month_start order by coalesce(pq.ViewCount,0) desc, coalesce(pq.Score,0) desc, coalesce(pq.upvotes - pq.downvotes,0) desc) as rank_views_score,
        dense_rank() over (partition by pq.month_start order by coalesce(pq.answer_count,0) desc) as rank_answers,
        ntile(10) over (partition by pq.month_start order by coalesce(pq.favorites,0) desc) as decile_favorites
    from per_question_features pq
),
outliers as (
    select
        rq.QuestionId,
        rq.month_start,
        case when rq.ViewCount > 3 * (select avg(ViewCount) from per_question_features p where p.month_start = rq.month_start) then 1 else 0 end as view_outlier,
        case when rq.Score < (select avg(Score) - 2*stddev_pop(Score) from per_question_features p where p.month_start = rq.month_start) then 1 else 0 end as low_score_outlier
    from ranked_questions rq
),
monthly_tag_top as (
    select
        t.month_start,
        t.tag,
        sum(q.Score) as tag_score,
        row_number() over (partition by t.month_start order by sum(q.Score) desc NULLS LAST) as rn
    from tag_expanded t
    join questions q on q.Id = t.QuestionId
    group by t.month_start, t.tag
),
user_rep_changes as (
    select
        u.Id as UserId,
        date_trunc('month', u.CreationDate) as created_month,
        case
            when u.Reputation is null then null
            when u.Reputation < 100 then 'newbie'
            when u.Reputation < 1000 then 'intermediate'
            else 'expert'
        end as rep_band
    from Users u
),
final_agg as (
    select
        rq.month_start,
        rq.QuestionId,
        rq.Score,
        rq.ViewCount,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.answer_count,
        rq.rank_views_score,
        rq.rank_answers,
        rq.decile_favorites,
        rq.has_accepted_answer,
        rq.hours_to_accept,
        rq.owner_rep,
        rq.rep_bucket,
        rq.gold, rq.silver, rq.bronze, rq.tag_badges,
        rq.ever_closed,
        rq.ever_reopened,
        rq.community_bump,
        rq.howto_flag,
        rq.title_len,
        rq.body_text_len,
        o.view_outlier,
        o.low_score_outlier,
        mt.questions_with_tag as month_tag_volume,
        mtop.tag as month_top_tag,
        mtop.tag_score as month_top_tag_score,
        mr.questions as month_questions,
        mr.with_accepted as month_with_accepted,
        mr.avg_views as month_avg_views,
        mr.median_score as month_median_score
    from ranked_questions rq
    left join outliers o on o.QuestionId = rq.QuestionId and o.month_start = rq.month_start
    left join lateral (
        select sum(questions_with_tag) as questions_with_tag
        from monthly_tag_stats ts
        where ts.month_start = rq.month_start
          and exists (
              select 1
              from tag_expanded te
              where te.QuestionId = rq.QuestionId
                and te.tag = ts.tag
          )
    ) mt on true
    left join monthly_rollup mr on mr.month_start = rq.month_start
    left join monthly_tag_top mtop on mtop.month_start = rq.month_start and mtop.rn = 1
)
select *
from final_agg
where coalesce(ViewCount,0) + coalesce(upvotes,0) + coalesce(favorites,0) > 0
order by month_start desc, rank_views_score asc
limit 500;