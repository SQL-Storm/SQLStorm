-- {"query": "163.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4024} 
with
params as (
    select
        date_trunc('month', now()) - interval '24 months' as start_month,
        now() as as_of
),
-- Active users with activity score
active_users as (
    select
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        coalesce(u.Location, 'Unknown') as Location,
        u.CreationDate,
        u.LastAccessDate,
        (coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0)) as net_votes,
        row_number() over (order by (coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0)) desc, u.Reputation desc, u.Id) as rn_net_votes
    from Users u
    where u.CreationDate <= (select as_of from params)
),
-- Monthly question metrics
q_monthly as (
    select
        date_trunc('month', p.CreationDate) as month,
        p.OwnerUserId as user_id,
        count(*) filter (where p.PostTypeId = 1) as questions,
        count(*) filter (where p.PostTypeId = 2) as answers,
        avg(nullif(p.Score,0)) filter (where p.PostTypeId = 1) as avg_q_score_nonzero,
        avg(p.ViewCount) filter (where p.PostTypeId = 1) as avg_q_views,
        sum(p.FavoriteCount) filter (where p.PostTypeId = 1) as favs
    from Posts p
    where p.CreationDate >= (select start_month from params)
      and p.CreationDate < (select as_of from params)
      and p.PostTypeId in (1,2)
    group by 1,2
),
-- Answer acceptance and speed
answer_accept as (
    select
        a.OwnerUserId as user_id,
        date_trunc('month', a.CreationDate) as month,
        count(*) filter (
            where exists (
                select 1
                from Posts q
                where q.Id = a.ParentId
                  and q.AcceptedAnswerId = a.Id
            )
        ) as accepted_answers,
        avg(extract(epoch from (q.CreationDate - a.CreationDate)) / 3600.0) filter (
            where q.AcceptedAnswerId = a.Id
        ) as avg_hours_early_accept  -- negative means answered after question creation
    from Posts a
    join Posts q on q.Id = a.ParentId and a.PostTypeId = 2 and q.PostTypeId = 1
    where a.CreationDate >= (select start_month from params)
      and a.CreationDate < (select as_of from params)
    group by 1,2
),
-- Comments with sentiment proxy and length bins
cmt_monthly as (
    select
        date_trunc('month', c.CreationDate) as month,
        c.UserId as user_id,
        count(*) as comments,
        avg(c.Score) as avg_c_score,
        percentile_cont(0.5) within group (order by length(coalesce(c.Text,''))) as p50_len,
        sum(case when c.Text ilike '%thanks%' or c.Text ilike '%thank you%' then 1 else 0 end) as thanks_like,
        sum(case when c.Text ilike '%?%' then 1 else 0 end) as questions_like
    from Comments c
    where c.CreationDate >= (select start_month from params)
      and c.CreationDate < (select as_of from params)
      and c.UserId is not null
    group by 1,2
),
-- Badge acquisition
badge_monthly as (
    select
        date_trunc('month', b.Date) as month,
        b.UserId as user_id,
        count(*) as badges,
        count(*) filter (where b.Class = 1) as gold,
        count(*) filter (where b.Class = 2) as silver,
        count(*) filter (where b.Class = 3) as bronze,
        count(*) filter (where b.TagBased = 1) as tag_based
    from Badges b
    where b.Date >= (select start_month from params)
      and b.Date < (select as_of from params)
    group by 1,2
),
-- Close/duplicate events and reasons (from PostHistory)
close_events as (
    select
        date_trunc('month', ph.CreationDate) as month,
        p.OwnerUserId as user_id,
        count(*) filter (where ph.PostHistoryTypeId = 10) as closes,
        count(*) filter (where ph.PostHistoryTypeId = 11) as reopens,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment::int = 101) as dup_votes,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment::int = 102) as offtopic_votes
    from PostHistory ph
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId in (10,11)
      and ph.CreationDate >= (select start_month from params)
      and ph.CreationDate < (select as_of from params)
    group by 1,2
),
-- Post link structure (duplicates and linked density)
link_metrics as (
    select
        date_trunc('month', pl.CreationDate) as month,
        q.OwnerUserId as user_id,
        count(*) filter (where pl.LinkTypeId = 3) as dup_links_out,
        count(*) filter (where pl.LinkTypeId = 1) as links_out,
        count(distinct pl.RelatedPostId) as distinct_targets
    from PostLinks pl
    join Posts q on q.Id = pl.PostId
    where pl.CreationDate >= (select start_month from params)
      and pl.CreationDate < (select as_of from params)
    group by 1,2
),
-- Votes aggregation by type
vote_monthly as (
    select
        date_trunc('month', v.CreationDate) as month,
        p.OwnerUserId as user_id,
        count(*) filter (where v.VoteTypeId = 2) as upvotes,
        count(*) filter (where v.VoteTypeId = 3) as downvotes,
        count(*) filter (where v.VoteTypeId = 5) as favorites,
        count(*) filter (where v.VoteTypeId = 8) as bounty_start,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as bounty_amount
    from Votes v
    join Posts p on p.Id = v.PostId
    where v.CreationDate >= (select start_month from params)
      and v.CreationDate < (select as_of from params)
    group by 1,2
),
-- Monthly user tag entropy proxy via question tag strings
tag_signal as (
    select
        date_trunc('month', p.CreationDate) as month,
        p.OwnerUserId as user_id,
        count(*) as tagged_qs,
        avg(coalesce(array_length(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><'), 1), 0)) as avg_tag_count,
        sum(case when p.Tags ilike '%<sql>%' then 1 else 0 end) as sql_qs
    from Posts p
    where p.PostTypeId = 1
      and p.OwnerUserId is not null
      and p.CreationDate >= (select start_month from params)
      and p.CreationDate < (select as_of from params)
    group by 1,2
),
-- Build calendar months for complete outer joining
months as (
    select generate_series((select start_month from params), (select date_trunc('month', (select as_of from params))), interval '1 month') as month
),
-- Combine per-user per-month metrics (sparse)
combined_sparse as (
    select
        coalesce(qm.month, am.month, cm.month, bm.month, ce.month, lm.month, vm.month, ts.month) as month,
        coalesce(qm.user_id, am.user_id, cm.user_id, bm.user_id, ce.user_id, lm.user_id, vm.user_id, ts.user_id) as user_id,
        qm.questions,
        qm.answers,
        qm.avg_q_score_nonzero,
        qm.avg_q_views,
        qm.favs,
        am.accepted_answers,
        am.avg_hours_early_accept,
        cm.comments,
        cm.avg_c_score,
        cm.p50_len,
        cm.thanks_like,
        cm.questions_like,
        bm.badges,
        bm.gold,
        bm.silver,
        bm.bronze,
        bm.tag_based,
        ce.closes,
        ce.reopens,
        ce.dup_votes,
        ce.offtopic_votes,
        lm.dup_links_out,
        lm.links_out,
        lm.distinct_targets,
        vm.upvotes,
        vm.downvotes,
        vm.favorites,
        vm.bounty_start,
        vm.bounty_amount,
        ts.tagged_qs,
        ts.avg_tag_count,
        ts.sql_qs
    from q_monthly qm
    full outer join answer_accept am on am.month = qm.month and am.user_id = qm.user_id
    full outer join cmt_monthly cm on cm.month = coalesce(qm.month, am.month) and cm.user_id = coalesce(qm.user_id, am.user_id)
    full outer join badge_monthly bm on bm.month = coalesce(qm.month, am.month, cm.month) and bm.user_id = coalesce(qm.user_id, am.user_id, cm.user_id)
    full outer join close_events ce on ce.month = coalesce(qm.month, am.month, cm.month, bm.month) and ce.user_id = coalesce(qm.user_id, am.user_id, cm.user_id, bm.user_id)
    full outer join link_metrics lm on lm.month = coalesce(qm.month, am.month, cm.month, bm.month, ce.month) and lm.user_id = coalesce(qm.user_id, am.user_id, cm.user_id, bm.user_id, ce.user_id)
    full outer join vote_monthly vm on vm.month = coalesce(qm.month, am.month, cm.month, bm.month, ce.month, lm.month) and vm.user_id = coalesce(qm.user_id, am.user_id, cm.user_id, bm.user_id, ce.user_id, lm.user_id)
    full outer join tag_signal ts on ts.month = coalesce(qm.month, am.month, cm.month, bm.month, ce.month, lm.month, vm.month) and ts.user_id = coalesce(qm.user_id, am.user_id, cm.user_id, bm.user_id, ce.user_id, lm.user_id, vm.user_id)
),
-- Dense month grid for each active user
user_months as (
    select
        m.month,
        au.user_id,
        au.DisplayName,
        au.Reputation,
        au.Location
    from months m
    cross join lateral (
        select user_id, DisplayName, Reputation, Location
        from active_users
        where rn_net_votes <= 5000
    ) au
    where m.month >= (select start_month from params)
),
-- Join metrics onto dense grid and compute derived KPIs with NULL logic
user_month_kpis as (
    select
        um.month,
        um.user_id,
        um.DisplayName,
        um.Reputation,
        um.Location,
        coalesce(cs.questions,0) as questions,
        coalesce(cs.answers,0) as answers,
        coalesce(cs.accepted_answers,0) as accepted_answers,
        case when coalesce(cs.answers,0) > 0 then coalesce(cs.accepted_answers,0)::float / nullif(cs.answers,0) else null end as accept_rate,
        coalesce(cs.upvotes,0) - coalesce(cs.downvotes,0) as net_votes_delta,
        coalesce(cs.avg_q_score_nonzero,0) as avg_q_score_nonzero,
        coalesce(cs.avg_q_views,0) as avg_q_views,
        coalesce(cs.favs,0) + coalesce(cs.favorites,0) as favorites_total,
        coalesce(cs.comments,0) as comments,
        coalesce(cs.avg_c_score,0) as avg_c_score,
        coalesce(cs.p50_len,0) as p50_comment_len,
        coalesce(cs.badges,0) as badges,
        coalesce(cs.gold,0) as gold,
        coalesce(cs.silver,0) as silver,
        coalesce(cs.bronze,0) as bronze,
        coalesce(cs.closes,0) as closes,
        coalesce(cs.reopens,0) as reopens,
        coalesce(cs.dup_votes,0) as dup_votes,
        coalesce(cs.offtopic_votes,0) as offtopic_votes,
        coalesce(cs.dup_links_out,0) as dup_links_out,
        coalesce(cs.links_out,0) as links_out,
        coalesce(cs.distinct_targets,0) as distinct_targets,
        coalesce(cs.bounty_start,0) as bounty_start,
        coalesce(cs.bounty_amount,0) as bounty_amount,
        coalesce(cs.tagged_qs,0) as tagged_qs,
        coalesce(cs.avg_tag_count,0) as avg_tag_count,
        coalesce(cs.sql_qs,0) as sql_qs,
        -- composite engagement index
        (
            1.0 * coalesce(cs.questions,0)
          + 0.7 * coalesce(cs.answers,0)
          + 0.2 * greatest(coalesce(cs.upvotes,0) - coalesce(cs.downvotes,0), 0)
          + 0.1 * coalesce(cs.comments,0)
          + 0.3 * coalesce(cs.badges,0)
          + 0.5 * coalesce(cs.bounty_start,0)
        ) as engagement_score,
        -- quality proxy
        (
            0.6 * coalesce(cs.avg_q_score_nonzero,0)
          + 0.3 * case when coalesce(cs.answers,0) > 0 then coalesce(cs.accepted_answers,0)::float / nullif(cs.answers,0) else 0 end
          + 0.1 * least(coalesce(cs.offtopic_votes,0), 5)
        ) as quality_score
    from user_months um
    left join combined_sparse cs
      on cs.month = um.month and cs.user_id = um.user_id
),
-- Window functions across months per user
user_month_windowed as (
    select
        *,
        sum(engagement_score) over (partition by user_id order by month rows between 11 preceding and current row) as engagement_12mo,
        sum(quality_score) over (partition by user_id order by month rows between 11 preceding and current row) as quality_12mo,
        avg(accept_rate) over (partition by user_id order by month rows between 2 preceding and current row) as accept_rate_3mo_avg,
        lead(engagement_score) over (partition by user_id order by month) as engagement_next,
        lag(engagement_score) over (partition by user_id order by month) as engagement_prev
    from user_month_kpis
),
-- Rank users each month by multiple criteria
ranked as (
    select
        umw.*,
        row_number() over (partition by month order by engagement_12mo desc nulls last, quality_12mo desc nulls last, Reputation desc nulls last) as rank_overall,
        dense_rank() over (partition by month order by coalesce(accept_rate_3mo_avg,0) desc) as rank_accept_avg,
        ntile(4) over (partition by month order by net_votes_delta desc nulls last) as net_votes_quartile
    from user_month_windowed umw
),
-- Identify monthly outliers and trend flags
flags as (
    select
        r.*,
        case
            when r.engagement_score > coalesce(r.engagement_prev, 0) * 1.5 and r.engagement_score >= 10 then 1
            else 0
        end as surge_flag,
        case
            when r.engagement_score < coalesce(r.engagement_prev, 0) * 0.5 and r.engagement_prev is not null then 1
            else 0
        end as drop_flag,
        case when r.net_votes_quartile = 4 then 1 else 0 end as top_quartile_net_votes
    from ranked r
),
-- Summarize per month with top-k users and aggregates
month_summary as (
    select
        f.month,
        count(*) as users_considered,
        avg(f.engagement_score) as avg_engagement,
        avg(f.quality_score) as avg_quality,
        sum(case when f.rank_overall <= 50 then 1 else 0 end) as top50_users,
        sum(f.surge_flag) as surges,
        sum(f.drop_flag) as drops
    from flags f
    group by 1
),
-- Prepare a final rowset with unioned detail and summary using set operators
final_rows as (
    select
        to_char(f.month, 'YYYY-MM') as period,
        f.user_id,
        coalesce(nullif(trim(f.DisplayName), ''), '(anon)') as display_name,
        f.Location,
        f.rank_overall,
        f.engagement_12mo,
        f.quality_12mo,
        f.accept_rate_3mo_avg,
        f.net_votes_quartile,
        f.surge_flag,
        f.drop_flag,
        f.questions,
        f.answers,
        f.accepted_answers,
        f.net_votes_delta,
        f.badges,
        f.bounty_amount,
        f.tagged_qs,
        f.sql_qs
    from flags f
    where f.rank_overall <= 200
    union all
    select
        to_char(ms.month, 'YYYY-MM') as period,
        null as user_id,
        '[summary]' as display_name,
        null as Location,
        null as rank_overall,
        null as engagement_12mo,
        null as quality_12mo,
        null as accept_rate_3mo_avg,
        null as net_votes_quartile,
        null as surge_flag,
        null as drop_flag,
        null as questions,
        null as answers,
        null as accepted_answers,
        null as net_votes_delta,
        null as badges,
        null as bounty_amount,
        null as tagged_qs,
        null as sql_qs
    from month_summary ms
)
select *
from final_rows
order by period desc, rank_overall nulls last, user_id nulls last
limit 5000;