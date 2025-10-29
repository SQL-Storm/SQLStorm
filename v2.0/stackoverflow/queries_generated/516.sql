-- {"query": "516.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2645} 
with params as (
    select
        now() - interval '365 days' as since_date,
        100 as min_rep,
        5 as min_answers,
        50 as min_views
),
active_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           max(p.lastactivitydate) as last_activity,
           sum(greatest(p.viewcount,0)) as total_views
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, u.displayname, u.reputation, region
),
recent_posts as (
    select p.id,
           p.posttypeid,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.parentid,
           p.acceptedanswerid
    from posts p
    join params pr on p.creationdate >= pr.since_date
),
tag_explode as (
    select rp.id as post_id,
           unnest(string_to_array(substring(coalesce(rp.tags, ''), 2, greatest(length(coalesce(rp.tags,'')) - 2, 0)), '><')) as tag
    from recent_posts rp
    where rp.posttypeid = 1
),
tag_stats as (
    select te.tag,
           count(*) as q_cnt,
           sum(rp.viewcount) as q_views,
           percentile_cont(0.5) within group (order by rp.score) as median_q_score
    from tag_explode te
    join recent_posts rp on rp.id = te.post_id
    group by te.tag
    having count(*) >= 10
),
answer_activity as (
    select a.parentid as question_id,
           count(*) as answers_last_year,
           sum(case when a.score > 0 then 1 else 0 end) as pos_answers,
           max(a.creationdate) as last_answer_date
    from recent_posts a
    where a.posttypeid = 2
    group by a.parentid
),
question_enriched as (
    select q.id as question_id,
           q.title,
           q.score as q_score,
           greatest(q.viewcount,0) as q_views,
           q.creationdate as q_created,
           q.acceptedanswerid,
           au.user_id as owner_id,
           au.displayname as owner_name,
           au.reputation as owner_rep,
           au.region,
           ts.tag as primary_tag,
           ts.q_cnt as tag_q_count,
           ts.q_views as tag_q_views,
           ts.median_q_score as tag_median_score,
           aa.answers_last_year,
           aa.pos_answers,
           aa.last_answer_date
    from recent_posts q
    left join active_users au on au.user_id = q.owneruserid
    left join lateral (
        select te.tag
        from tag_explode te
        where te.post_id = q.id
        order by te.tag
        limit 1
    ) ts0 on true
    left join tag_stats ts on ts.tag = ts0.tag
    left join answer_activity aa on aa.question_id = q.id
    where q.posttypeid = 1
),
vote_agg as (
    select v.postid,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount
    from votes v
    join params p on v.creationdate >= p.since_date
    group by v.postid
),
comment_pulse as (
    select c.postid,
           count(*) as comment_count,
           max(c.creationdate) as last_comment_date,
           avg(c.score) as avg_comment_score
    from comments c
    join params p on c.creationdate >= p.since_date
    group by c.postid
),
post_link_flags as (
    select pl.postid,
           bool_or(pl.linktypeid = 3) as has_duplicate_flag,
           count(*) filter (where pl.linktypeid = 3) as dup_count,
           count(*) filter (where pl.linktypeid = 1) as linked_count,
           max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
closure_info as (
    select ph.postid,
           min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
           min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopen_date,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events,
           count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
           max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
quality_signals as (
    select qe.question_id,
           coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
           coalesce(va.favorites,0) as favorites,
           coalesce(va.bounty_amount,0) as bounty_amount,
           coalesce(cp.comment_count,0) as comments,
           coalesce(cp.avg_comment_score,0) as avg_comment_score,
           pl.has_duplicate_flag,
           coalesce(pl.dup_count,0) as dup_count,
           coalesce(pl.linked_count,0) as linked_count,
           ci.first_close_date,
           ci.first_reopen_date,
           coalesce(ci.close_events,0) as close_events,
           coalesce(ci.reopen_events,0) as reopen_events,
           ci.last_close_reason_id
    from question_enriched qe
    left join vote_agg va on va.postid = qe.question_id
    left join comment_pulse cp on cp.postid = qe.question_id
    left join post_link_flags pl on pl.postid = qe.question_id
    left join closure_info ci on ci.postid = qe.question_id
),
owner_badges as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
scored_questions as (
    select
        qe.*,
        qs.net_votes,
        qs.favorites,
        qs.bounty_amount,
        qs.comments,
        qs.avg_comment_score,
        qs.has_duplicate_flag,
        qs.dup_count,
        qs.linked_count,
        qs.first_close_date,
        qs.first_reopen_date,
        qs.close_events,
        qs.reopen_events,
        qs.last_close_reason_id,
        ob.gold_badges,
        ob.silver_badges,
        ob.bronze_badges,
        ob.tag_badges,
        case
            when qe.acceptedanswerid is not null then 1 else 0
        end as has_accepted,
        coalesce(qe.answers_last_year,0) as answers_last_year_nz,
        coalesce(qe.pos_answers,0) as pos_answers_nz
    from question_enriched qe
    left join quality_signals qs on qs.question_id = qe.question_id
    left join owner_badges ob on ob.userid = qe.owner_id
),
ranked as (
    select
        sq.*,
        row_number() over (
            partition by coalesce(sq.primary_tag, '_none')
            order by
                (coalesce(sq.net_votes,0) * 1.0) +
                (coalesce(sq.favorites,0) * 0.5) +
                (coalesce(sq.q_views,0) / nullif(greatest(sq.tag_q_views,1),0)::numeric) * 10 +
                (case when sq.has_accepted = 1 then 5 else 0 end) +
                (least(coalesce(sq.answers_last_year_nz,0), 20) * 0.3) +
                (coalesce(sq.bounty_amount,0) / 50.0) -
                (coalesce(sq.dup_count,0) * 2) -
                (case when sq.first_close_date is not null and sq.first_reopen_date is null then 8 else 0 end)
            desc,
                sq.q_created desc
        ) as tag_rank,
        rank() over (
            order by
                (coalesce(sq.net_votes,0) * 1.0) +
                (coalesce(sq.favorites,0) * 0.5) +
                (coalesce(sq.q_views,0) / 1000.0) +
                (case when sq.has_accepted = 1 then 5 else 0 end) +
                (least(coalesce(sq.answers_last_year_nz,0), 20) * 0.3) +
                (coalesce(sq.bounty_amount,0) / 50.0) -
                (coalesce(sq.dup_count,0) * 2)
            desc,
                sq.q_created desc
        ) as global_rank
    from scored_questions sq
),
constraints as (
    select
        r.*,
        case when r.owner_rep >= (select min_rep from params) then 1 else 0 end as rep_ok,
        case when coalesce(r.answers_last_year_nz,0) >= (select min_answers from params) then 1 else 0 end as answers_ok,
        case when coalesce(r.q_views,0) >= (select min_views from params) then 1 else 0 end as views_ok
    from ranked r
),
final as (
    select
        c.question_id,
        c.title,
        c.primary_tag,
        c.owner_name,
        c.owner_rep,
        c.region,
        c.q_score,
        c.q_views,
        c.net_votes,
        c.favorites,
        c.bounty_amount,
        c.comments,
        c.has_accepted,
        c.answers_last_year_nz as answers_last_year,
        c.pos_answers_nz as positive_answers_last_year,
        c.close_events,
        c.reopen_events,
        c.last_close_reason_id,
        c.tag_rank,
        c.global_rank,
        (c.rep_ok + c.answers_ok + c.views_ok) as pass_count,
        case when c.has_duplicate_flag then 'DUP' else 'OK' end as dup_flag,
        coalesce(nullif(c.primary_tag, ''), '_none') || ':' ||
        coalesce(nullif(c.region, ''), 'Unknown') as bucket
    from constraints c
    where (c.rep_ok + c.answers_ok + c.views_ok) >= 2
)
select
    f.bucket,
    count(*) as questions,
    avg(f.q_score) as avg_q_score,
    percentile_cont(0.9) within group (order by f.q_views) as p90_views,
    min(f.global_rank) as best_global_rank,
    count(*) filter (where f.dup_flag = 'DUP') as dup_questions,
    sum(f.bounty_amount) as total_bounty,
    string_agg(distinct f.primary_tag, ', ' order by f.primary_tag) as tags_sample,
    string_agg(
        left(regexp_replace(coalesce(f.title,''), '\s+', ' ', 'g'), 60),
        ' | ' order by f.global_rank
    ) as titles_sample
from final f
group by f.bucket
having count(*) >= 3
order by questions desc, p90_views desc, bucket asc
limit 50;