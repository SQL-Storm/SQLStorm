-- {"query": "764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3211}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        date_trunc('month', p.CreationDate) as q_month
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
answer_stats as (
    select
        q.QuestionId,
        count(a.Id) as answer_count,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as answered_by_users,
        max(a.Score) as max_answer_score,
        min(a.CreationDate) filter (where a.CreationDate is not null) as first_answer_at
    from recent_questions q
    left join Posts a
        on a.ParentId = q.QuestionId
       and a.PostTypeId = 2
    group by q.QuestionId
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_total
    from Votes v
    where v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as comment_count,
        max(c.Score) as max_comment_score,
        max(c.CreationDate) as last_comment_at
    from Comments c
    where c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    group by c.PostId
),
tag_expanded as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as tag
    from recent_questions q
),
tag_rank as (
    select
        te.tag,
        count(*) as tag_q_count,
        rank() over (order by count(*) desc, min(te.tag)) as tag_rank_overall
    from tag_expanded te
    group by te.tag
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        coalesce(u.Location,'') as Location,
        -- emulate width_bucket(u.Reputation, 0, 100000, 10) in standard SQL:
        least(10, greatest(1, cast(floor( (u.Reputation::numeric - 0) / nullif((100000.0 - 0)/10.0,0) ) + 1 as integer))) as rep_bucket
    from Users u
),
question_history_flags as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as was_closed,
        max(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.PostHistoryTypeId = 19 then 1 else 0 end) as was_protected,
        max(case when ph.PostHistoryTypeId = 50 then 1 else 0 end) as was_bumped
    from PostHistory ph
    where ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
      and ph.PostId is not null
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as duplicate_links,
        count(*) filter (where pl.LinkTypeId = 1) as related_links
    from PostLinks pl
    where pl.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    group by pl.PostId
),
monthly_question_rollup as (
    select
        q.q_month,
        count(*) as questions_in_month,
        cast(avg(q.Score) as numeric(12,4)) as avg_q_score,
        cast(avg(q.ViewCount) as numeric(12,4)) as avg_q_views,
        percentile_disc(0.5) within group (order by q.ViewCount) as p50_views,
        percentile_disc(0.9) within group (order by q.ViewCount) as p90_views
    from recent_questions q
    group by q.q_month
),
accepted_answer_delta as (
    select
        q.Id as QuestionId,
        case
            when q.AcceptedAnswerId is null then null
            else
                (select a.CreationDate from Posts a where a.Id = q.AcceptedAnswerId)
        end as accepted_at
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
question_enriched as (
    select
        q.QuestionId,
        q.CreationDate,
        q.q_month,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.favorites,0) as favorites,
        coalesce(v.bounty_total,0) as bounty_total,
        coalesce(c.comment_count,0) as comment_count,
        c.last_comment_at,
        coalesce(a.answer_count,0) as answer_count,
        a.answered_by_users,
        a.max_answer_score,
        a.first_answer_at,
        coalesce(h.was_closed,0) as was_closed,
        coalesce(h.was_reopened,0) as was_reopened,
        coalesce(h.was_protected,0) as was_protected,
        coalesce(h.was_bumped,0) as was_bumped,
        coalesce(d.duplicate_links,0) as duplicate_links,
        coalesce(d.related_links,0) as related_links,
        aa.accepted_at
    from recent_questions q
    left join vote_agg v on v.PostId = q.QuestionId
    left join comment_agg c on c.PostId = q.QuestionId
    left join answer_stats a on a.QuestionId = q.QuestionId
    left join question_history_flags h on h.PostId = q.QuestionId
    left join dup_links d on d.PostId = q.QuestionId
    left join accepted_answer_delta aa on aa.QuestionId = q.QuestionId
),
scored as (
    select
        qe.*,
        cast((
            coalesce(qe.upvotes,0) * 3
          - coalesce(qe.downvotes,0) * 2
          + coalesce(qe.favorites,0) * 1
          + least(coalesce(qe.ViewCount,0), 10000) / 50.0
          + coalesce(qe.answer_count,0) * 4
          + coalesce(qe.max_answer_score,0) * 2
          + case when qe.was_bumped = 1 then 5 else 0 end
          - case when qe.was_closed = 1 then 10 else 0 end
          + case when qe.duplicate_links > 0 then -5 else 0 end
          + case when qe.last_comment_at >= qe.CreationDate + interval '1 day' then 2 else 0 end
        ) as numeric(18,4)) as engagement_score,
        extract(epoch from (qe.first_answer_at - qe.CreationDate)) / 60.0 as t_first_answer_min,
        extract(epoch from (qe.accepted_at - qe.CreationDate)) / 60.0 as t_accepted_min
    from question_enriched qe
),
normalized as (
    select
        s.*,
        (s.engagement_score - avg(s.engagement_score) over ()) / nullif(stddev_pop(s.engagement_score) over (),0) as eng_z,
        (s.ViewCount - avg(s.ViewCount) over ()) / nullif(stddev_pop(s.ViewCount) over (),0) as views_z,
        (s.Score - avg(s.Score) over ()) / nullif(stddev_pop(s.Score) over (),0) as score_z,
        row_number() over (order by s.engagement_score desc, s.ViewCount desc) as rn_engagement,
        dense_rank() over (partition by s.q_month order by s.engagement_score desc) as monthly_rank
    from scored s
),
tag_coverage as (
    select
        n.QuestionId,
        count(distinct te.tag) as tag_count,
        string_agg(te.tag, ',' order by te.tag) as tags_csv,
        max(case when tr.tag_rank_overall <= 50 then 1 else 0 end) as has_top50_tag
    from normalized n
    left join tag_expanded te on te.QuestionId = n.QuestionId
    left join tag_rank tr on tr.tag = te.tag
    group by n.QuestionId
),
user_join as (
    select
        n.*,
        us.Reputation,
        us.UpVotes as user_upvotes,
        us.DownVotes as user_downvotes,
        us.Views as user_views,
        us.Location,
        us.rep_bucket
    from normalized n
    left join user_stats us on us.UserId = n.OwnerUserId
),
final_set as (
    select
        uj.QuestionId,
        uj.Title,
        uj.Tags,
        tc.tags_csv,
        tc.tag_count,
        tc.has_top50_tag,
        uj.OwnerUserId,
        uj.Reputation,
        uj.Location,
        uj.rep_bucket,
        uj.CreationDate,
        uj.q_month,
        uj.Score,
        uj.ViewCount,
        uj.upvotes,
        uj.downvotes,
        uj.favorites,
        uj.bounty_total,
        uj.comment_count,
        uj.answer_count,
        uj.max_answer_score,
        uj.first_answer_at,
        uj.accepted_at,
        uj.was_closed,
        uj.was_reopened,
        uj.was_protected,
        uj.was_bumped,
        uj.duplicate_links,
        uj.related_links,
        uj.last_comment_at,
        uj.engagement_score,
        uj.eng_z,
        uj.views_z,
        uj.score_z,
        uj.rn_engagement,
        uj.monthly_rank,
        uj.t_first_answer_min,
        uj.t_accepted_min
    from user_join uj
    left join tag_coverage tc on tc.QuestionId = uj.QuestionId
),
high_vs_low as (
    select QuestionId from final_set where engagement_score >= (select percentile_disc(0.8) within group (order by engagement_score) from final_set)
    union
    select QuestionId from final_set where answer_count >= (select percentile_disc(0.8) within group (order by answer_count) from final_set)
),
null_heavy as (
    select
        fs.QuestionId,
        case when fs.accepted_at is null then 'no_accept' else 'accepted' end as accept_flag,
        case when fs.first_answer_at is null then 'no_answer' else 'answered' end as answer_flag
    from final_set fs
)
select
    fs.QuestionId,
    coalesce(fs.Title, '[no title]') as Title,
    coalesce(fs.tags_csv, '') as TagsCsv,
    fs.tag_count,
    fs.has_top50_tag,
    fs.OwnerUserId,
    coalesce(fs.Reputation, -1) as OwnerReputation,
    nullif(trim(fs.Location), '') as OwnerLocation,
    fs.rep_bucket,
    fs.CreationDate,
    fs.q_month,
    fs.Score,
    fs.ViewCount,
    fs.upvotes,
    fs.downvotes,
    fs.favorites,
    fs.bounty_total,
    fs.comment_count,
    fs.answer_count,
    fs.max_answer_score,
    fs.first_answer_at,
    fs.accepted_at,
    fs.was_closed,
    fs.was_reopened,
    fs.was_protected,
    fs.was_bumped,
    fs.duplicate_links,
    fs.related_links,
    fs.last_comment_at,
    round(fs.engagement_score, 4) as engagement_score,
    round(fs.eng_z, 4) as eng_z,
    round(fs.views_z, 4) as views_z,
    round(fs.score_z, 4) as score_z,
    fs.rn_engagement,
    fs.monthly_rank,
    fs.t_first_answer_min,
    fs.t_accepted_min,
    (
        select string_agg(c2.Text, ' | ' order by c2.CreationDate desc)
        from (
            select c.Text, c.CreationDate
            from Comments c
            where c.PostId = fs.QuestionId
            order by c.CreationDate desc
            limit 3
        ) c2
    ) as last3_comments_text,
    cast(fs.ViewCount as numeric) / nullif(avg(fs.ViewCount) over (partition by fs.q_month),0) as view_ratio_month,
    fs.engagement_score / nullif(avg(fs.engagement_score) over (partition by fs.q_month),0) as eng_ratio_month,
    case
        when fs.was_closed = 1 then 'closed'
        when fs.engagement_score >= (select percentile_disc(0.9) within group (order by engagement_score) from final_set) then 'top10pct'
        when fs.engagement_score <= (select percentile_disc(0.1) within group (order by engagement_score) from final_set) then 'bottom10pct'
        else 'middle'
    end as engagement_bucket,
    case when exists (select 1 from high_vs_low hv where hv.QuestionId = fs.QuestionId) then 1 else 0 end as in_contrast_set,
    nh.accept_flag,
    nh.answer_flag
from final_set fs
left join null_heavy nh on nh.QuestionId = fs.QuestionId
where
    (
        fs.ViewCount >= 100
        or (fs.answer_count >= 1 and coalesce(fs.upvotes,0) - coalesce(fs.downvotes,0) >= 0)
        or (fs.Tags is not null and position('python' in lower(fs.Tags)) > 0)
    )
  and not (
        fs.was_closed = 1
        and fs.duplicate_links >= 1
        and coalesce(fs.favorites,0) < 2
    )
  and (
        fs.accepted_at is null
        or fs.t_accepted_min >= 0
    )
order by
    fs.monthly_rank nulls last,
    fs.rn_engagement
limit 500;