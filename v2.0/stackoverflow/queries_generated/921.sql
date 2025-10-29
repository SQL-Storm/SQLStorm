-- {"query": "921.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3007} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
active_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.lastactivitydate,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (
            select date_trunc('month', max(creationdate)) - interval '6 months'
            from posts
            where posttypeid = 1
        )
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner_id,
        a.score as answer_score,
        a.creationdate as answer_date
    from posts a
    where a.posttypeid = 2
),
commentary as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
votes_agg as (
    select
        v.postid as post_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        max(case when v.votetypeid in (8,9) then v.creationdate end) as last_bounty_date
    from votes v
    group by v.postid
),
badges_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
dupe_links as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_refs,
        count(*) filter (where pl.linktypeid = 1) as linked_refs,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
tag_counts as (
    select
        aq.question_id,
        t.tagname,
        t.count as global_tag_count
    from active_questions aq
    left join lateral (
        select unnest(string_to_array(substring(aq.tags, 2, length(aq.tags)-2), '><')) as tagname
    ) xt on true
    left join tags t on lower(t.tagname) = lower(xt.tagname)
),
question_tag_stats as (
    select
        question_id,
        count(*) as tag_count,
        coalesce(avg(global_tag_count::numeric),0) as avg_global_tag_count,
        coalesce(max(global_tag_count),0) as max_global_tag_count
    from tag_counts
    group by question_id
),
answer_stats as (
    select
        aq.question_id,
        count(a.answer_id) as answer_count,
        max(a.answer_score) as max_answer_score,
        avg(a.answer_score::numeric) as avg_answer_score,
        min(a.answer_date) as first_answer_date,
        max(a.answer_date) as last_answer_date,
        count(*) filter (where a.answer_owner_id = aq.owneruserid) as self_answers
    from active_questions aq
    left join answers a on a.question_id = aq.question_id
    group by aq.question_id
),
accepted_answer as (
    select
        aq.question_id,
        a.answer_id as accepted_answer_id,
        a.answer_score as accepted_answer_score,
        a.answer_owner_id as accepted_answer_owner
    from active_questions aq
    left join answers a
      on a.answer_id = aq.acceptedanswerid
),
posthistory_flags as (
    select
        ph.postid as post_id,
        sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as closed_or_migrated_events,
        sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
        sum(case when ph.posthistorytypeid in (14) then 1 else 0 end) as locked_events,
        sum(case when ph.posthistorytypeid in (19) then 1 else 0 end) as protected_events,
        max(ph.creationdate) as last_ph_event
    from posthistory ph
    group by ph.postid
),
owner_activity as (
    select
        u.id as owner_id,
        u.reputation as owner_rep,
        coalesce(b.total_badges,0) as owner_badges,
        coalesce(b.gold_badges,0) as owner_gold,
        coalesce(b.silver_badges,0) as owner_silver,
        coalesce(b.bronze_badges,0) as owner_bronze,
        u.creationdate as owner_created
    from users u
    left join badges_agg b on b.userid = u.id
),
question_owner as (
    select
        aq.question_id,
        oa.owner_rep,
        oa.owner_badges,
        oa.owner_gold,
        oa.owner_silver,
        oa.owner_bronze,
        oa.owner_created
    from active_questions aq
    left join owner_activity oa on oa.owner_id = aq.owneruserid
),
recent_hot as (
    select
        aq.question_id,
        max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as was_hot,
        max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as was_unhot,
        max(case when ph.posthistorytypeid = 52 then ph.creationdate end) as hot_date
    from active_questions aq
    left join posthistory ph on ph.postid = aq.question_id
    group by aq.question_id
),
quality_scoring as (
    select
        aq.question_id,
        (
            coalesce(v.upvotes,0) * 2
            - coalesce(v.downvotes,0)
            + coalesce(a_s.max_answer_score,0)
            + case when aa.accepted_answer_id is not null then 5 else 0 end
            + case when coalesce(c.comment_count,0) > 5 then 2 else 0 end
            + case when rh.was_hot = 1 then 10 else 0 end
            + least(coalesce(qo.owner_rep,0)/1000, 20)
            - case when ph.closed_or_migrated_events > 0 then 8 else 0 end
            - case when aq.is_closed = 1 then 6 else 0 end
        )::numeric as raw_quality_score,
        coalesce(a_s.answer_count,0) as answers_n,
        coalesce(v.favorites,0) as favorites_n
    from active_questions aq
    left join votes_agg v on v.post_id = aq.question_id
    left join answer_stats a_s on a_s.question_id = aq.question_id
    left join accepted_answer aa on aa.question_id = aq.question_id
    left join commentary c on c.post_id = aq.question_id
    left join recent_hot rh on rh.question_id = aq.question_id
    left join question_owner qo on qo.question_id = aq.question_id
    left join posthistory_flags ph on ph.post_id = aq.question_id
),
ranked as (
    select
        aq.question_id,
        aq.title,
        aq.creationdate,
        aq.viewcount,
        aq.score as q_score,
        qs.raw_quality_score,
        qs.answers_n,
        qs.favorites_n,
        qt.tag_count,
        qt.avg_global_tag_count,
        qt.max_global_tag_count,
        v.upvotes,
        v.downvotes,
        v.bounty_total,
        v.last_bounty_date,
        coalesce(c.comment_count,0) as comment_count,
        coalesce(c.last_comment_date, aq.creationdate) as last_comment_date,
        d.duplicate_refs,
        d.linked_refs,
        d.last_link_date,
        rh.was_hot,
        aa.accepted_answer_id,
        aa.accepted_answer_score,
        row_number() over (
            order by
                (qs.raw_quality_score + coalesce(v.upvotes,0) - coalesce(v.downvotes,0) + log(greatest(aq.viewcount,1))) desc,
                aq.creationdate desc
        ) as overall_rank,
        dense_rank() over (order by qs.raw_quality_score desc) as quality_rank,
        percent_rank() over (order by qs.raw_quality_score) as quality_percentile,
        ntile(10) over (order by aq.viewcount desc) as view_decile,
        sum(coalesce(v.upvotes,0)) over (order by aq.creationdate rows between unbounded preceding and current row) as cumulative_upvotes
    from active_questions aq
    left join votes_agg v on v.post_id = aq.question_id
    left join commentary c on c.post_id = aq.question_id
    left join dupe_links d on d.question_id = aq.question_id
    left join recent_hot rh on rh.question_id = aq.question_id
    left join accepted_answer aa on aa.question_id = aq.question_id
    left join question_tag_stats qt on qt.question_id = aq.question_id
    left join quality_scoring qs on qs.question_id = aq.question_id
),
topk as (
    select *
    from ranked
    where overall_rank <= 200
),
owner_join as (
    select
        t.question_id,
        u.displayname as owner_name,
        u.location as owner_location,
        coalesce(nullif(u.websiteurl,''), 'N/A') as owner_website
    from topk t
    left join posts p on p.id = t.question_id
    left join users u on u.id = p.owneruserid
),
finalized as (
    select
        t.*,
        oj.owner_name,
        oj.owner_location,
        oj.owner_website,
        case
            when rh.was_hot = 1 then 'HOT'
            when t.q_score >= 5 and t.viewcount >= 1000 then 'TRENDING'
            when t.q_score < 0 then 'CONTROVERSIAL'
            else 'NORMAL'
        end as status_bucket,
        case
            when t.accepted_answer_id is null and t.answers_n > 0 then 'UNACCEPTED'
            when t.accepted_answer_id is not null then 'ACCEPTED'
            else 'UNANSWERED'
        end as acceptance_state
    from topk t
    left join owner_join oj on oj.question_id = t.question_id
    left join recent_hot rh on rh.question_id = t.question_id
)
select
    f.overall_rank,
    f.quality_rank,
    round(f.quality_percentile::numeric, 4) as quality_percentile,
    f.view_decile,
    f.question_id,
    coalesce(nullif(f.title,''), '[no title]') as title,
    f.owner_name,
    f.owner_location,
    f.owner_website,
    f.creationdate,
    f.last_comment_date,
    f.last_link_date,
    f.last_bounty_date,
    f.viewcount,
    f.q_score as question_score,
    f.upvotes,
    f.downvotes,
    f.comment_count,
    f.answers_n,
    f.accepted_answer_id,
    f.accepted_answer_score,
    f.favorites_n,
    f.bounty_total,
    f.tag_count,
    f.avg_global_tag_count,
    f.max_global_tag_count,
    f.duplicate_refs,
    f.linked_refs,
    f.status_bucket,
    f.acceptance_state,
    -- complicated predicate-derived flags
    case
        when f.was_hot = 1 and f.duplicate_refs > 0 then 'HOT_DUPLICATE'
        when f.was_hot = 1 then 'HOT_UNIQUE'
        when f.duplicate_refs > 0 then 'DUPLICATE_ONLY'
        else 'NEITHER'
    end as hot_dupe_combo,
    -- string expressions
    lower(regexp_replace(coalesce(nullif(f.title,''),'[no title]'), '\s+', ' ', 'g')) as normalized_title,
    substring(coalesce(nullif(f.title,''),'[no title]') from 1 for 120) as title_snippet,
    -- null logic example
    coalesce(f.accepted_answer_score, -9999) as accepted_answer_score_nvl,
    -- windowed re-rank within buckets
    row_number() over (partition by f.status_bucket order by f.raw_quality_score desc, f.viewcount desc) as rank_in_bucket
from finalized f
where (
        (f.was_hot = 1 and f.viewcount > 0)
        or (f.answers_n >= 2 and coalesce(f.accepted_answer_score,0) >= 0)
        or (f.duplicate_refs is null or f.duplicate_refs = 0)
      )
  and not (f.status_bucket = 'CONTROVERSIAL' and f.downvotes > f.upvotes)
order by f.overall_rank, f.quality_rank, f.question_id;