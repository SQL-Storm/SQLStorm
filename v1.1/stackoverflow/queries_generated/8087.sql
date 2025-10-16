-- {"query": "8087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3213} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn_user_recent
    from posts p
    where p.creationdate >= now() - interval '365 days'
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_creationdate,
        u.location,
        u.websiteurl,
        coalesce(u.upvotes - u.downvotes, 0) as net_votes,
        count(distinct c.id) filter (where c.creationdate >= now() - interval '365 days') as comments_last_year,
        count(distinct b.id) filter (where b.date >= now() - interval '365 days') as badges_last_year,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges_total,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges_total,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges_total
    from users u
    left join comments c on c.userid = u.id
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl, u.upvotes, u.downvotes
),
post_engagement as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.viewcount,
        p.score,
        p.answercount,
        p.commentcount,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(distinct c.id) as comments_count
    from posts p
    left join votes v on v.postid = p.id
    left join comments c on c.postid = p.id
    where p.creationdate >= now() - interval '365 days'
    group by p.id, p.posttypeid, p.owneruserid, p.creationdate, p.viewcount, p.score, p.answercount, p.commentcount
),
post_linkage as (
    select
        pl.postid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_of_count,
        max(case when pl.linktypeid = 3 then pl.relatedpostid end) as example_dupe_target
    from postlinks pl
    where pl.creationdate >= now() - interval '365 days'
    group by pl.postid
),
tag_explode as (
    select
        p.id as post_id,
        trim(t) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is not null and length(p.tags) > 2
            then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            else array[]::varchar[]
        end
    ) as t
    where p.posttypeid = 1
),
tag_stats as (
    select
        te.post_id,
        count(*) as tag_count,
        min(te.tag) as first_tag_alpha,
        max(te.tag) as last_tag_alpha
    from tag_explode te
    group by te.post_id
),
question_quality as (
    select
        pe.post_id,
        coalesce(pe.upvotes,0) - coalesce(pe.downvotes,0) as net_votes,
        coalesce(pe.favorites,0) as favorites,
        coalesce(pe.answercount,0) as answers,
        coalesce(pe.viewcount,0) as views,
        coalesce(ts.tag_count,0) as tag_count,
        -- heuristic score mixing various metrics with logarithms and null-safety
        (
            0.6 * ln(1 + greatest(coalesce(pe.viewcount,0),0)) +
            1.2 * greatest(coalesce(pe.upvotes,0) - coalesce(pe.downvotes,0), 0) +
            0.8 * least(coalesce(pe.answercount,0), 10) +
            0.5 * coalesce(pe.favorites,0) +
            0.2 * greatest(coalesce(ts.tag_count,0) - 2, 0)
        )::numeric(18,4) as quality_score
    from post_engagement pe
    left join tag_stats ts on ts.post_id = pe.post_id
),
post_closure as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
accepted_answer_latency as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.creationdate - q.creationdate as latency
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
question_windows as (
    select
        p.id as post_id,
        p.owneruserid,
        p.creationdate,
        row_number() over (partition by p.owneruserid order by p.creationdate) as seq_for_user,
        lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_post_date,
        lead(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as next_post_date
    from posts p
    where p.posttypeid = 1
),
user_recent_mix as (
    select
        rp.id as post_id,
        rp.owneruserid as user_id,
        rp.rn_user_recent,
        sum(case when pe.posttypeid = 2 then 1 else 0 end) as answers_authored_last_year,
        sum(case when pe.posttypeid = 1 then 1 else 0 end) as questions_authored_last_year
    from recent_posts rp
    left join post_engagement pe on pe.owneruserid = rp.owneruserid
    group by rp.id, rp.owneruserid, rp.rn_user_recent
),
dup_pairs as (
    select
        pl.postid as dupe_question_id,
        pl.relatedpostid as target_question_id
    from postlinks pl
    where pl.linktypeid = 3
),
dup_chain as (
    select
        d.dupe_question_id,
        d.target_question_id,
        1 as depth
    from dup_pairs d
    union all
    select
        dc.dupe_question_id,
        d2.target_question_id,
        dc.depth + 1
    from dup_chain dc
    join dup_pairs d2 on d2.dupe_question_id = dc.target_question_id
    where dc.depth < 3
),
dup_summary as (
    select
        dupe_question_id,
        min(target_question_id) as min_target,
        max(target_question_id) as max_target,
        max(depth) as max_depth,
        count(*) as chain_links
    from dup_chain
    group by dupe_question_id
),
final_posts as (
    select
        p.id as post_id,
        p.posttypeid,
        p.title,
        p.tags,
        p.owneruserid as user_id,
        pe.viewcount,
        pe.score,
        pe.answercount,
        pe.commentcount,
        coalesce(pl.linked_count,0) as linked_count,
        coalesce(pl.duplicate_of_count,0) as duplicate_of_count,
        qs.quality_score,
        pc.close_events,
        pc.reopen_events,
        pc.first_close_date,
        pc.last_close_date,
        aal.latency as accepted_latency,
        qw.seq_for_user,
        (extract(epoch from (now() - p.creationdate)) / 86400.0)::numeric(12,2) as age_days,
        ts.tag_count
    from posts p
    left join post_engagement pe on pe.post_id = p.id
    left join post_linkage pl on pl.postid = p.id
    left join question_quality qs on qs.post_id = p.id
    left join post_closure pc on pc.postid = p.id
    left join accepted_answer_latency aal on aal.question_id = p.id
    left join question_windows qw on qw.post_id = p.id
    left join tag_stats ts on ts.post_id = p.id
    where p.creationdate >= now() - interval '365 days'
),
rankings as (
    select
        fp.*,
        dense_rank() over (order by coalesce(fp.quality_score, -1) desc nulls last) as dr_quality,
        percent_rank() over (order by coalesce(fp.viewcount,0) desc) as pr_views,
        ntile(10) over (order by coalesce(fp.score, -100) desc) as decile_score
    from final_posts fp
),
user_rollup as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.location,
        ua.websiteurl,
        ua.net_votes,
        count(distinct case when rp.posttypeid = 1 then rp.id end) as questions_last_year,
        count(distinct case when rp.posttypeid = 2 then rp.id end) as answers_last_year,
        sum(coalesce(pe.viewcount,0)) as views_last_year,
        max(ua.badges_last_year) as badges_last_year,
        ua.gold_badges_total,
        ua.silver_badges_total,
        ua.bronze_badges_total
    from user_activity ua
    left join recent_posts rp on rp.owneruserid = ua.user_id
    left join post_engagement pe on pe.post_id = rp.id
    group by ua.user_id, ua.displayname, ua.reputation, ua.location, ua.websiteurl, ua.net_votes, ua.gold_badges_total, ua.silver_badges_total, ua.bronze_badges_total
),
aggregated as (
    select
        r.post_id,
        r.posttypeid,
        r.title,
        r.user_id,
        r.viewcount,
        r.score,
        r.answercount,
        r.commentcount,
        r.linked_count,
        r.duplicate_of_count,
        r.quality_score,
        r.close_events,
        r.reopen_events,
        r.first_close_date,
        r.last_close_date,
        r.accepted_latency,
        r.seq_for_user,
        r.age_days,
        r.tag_count,
        r.dr_quality,
        r.pr_views,
        r.decile_score,
        ur.displayname,
        ur.reputation,
        ur.net_votes,
        ur.questions_last_year,
        ur.answers_last_year,
        ur.views_last_year,
        ur.badges_last_year,
        ur.gold_badges_total,
        ur.silver_badges_total,
        ur.bronze_badges_total,
        ds.max_depth as dup_chain_depth
    from rankings r
    left join user_rollup ur on ur.user_id = r.user_id
    left join dup_summary ds on ds.dupe_question_id = r.post_id
),
stringified as (
    select
        a.*,
        coalesce(nullif(trim(a.title), ''), concat('[post-', a.post_id::varchar, ']')) as safe_title,
        case
            when a.duplicate_of_count > 0 then 'DUPLICATE'
            when a.close_events > 0 and coalesce(a.reopen_events,0) = 0 then 'CLOSED'
            when a.posttypeid = 2 then 'ANSWER'
            when a.posttypeid = 1 then 'QUESTION'
            else 'OTHER'
        end as post_state,
        concat_ws(' | ',
            'User: ' || coalesce(a.displayname, '<unknown>'),
            'Rep: ' || coalesce(a.reputation::varchar, '0'),
            'NetVotes: ' || coalesce(a.net_votes::varchar, '0')
        ) as user_summary
    from aggregated a
)
select
    s.post_id,
    s.safe_title as title,
    s.post_state,
    s.user_summary,
    s.viewcount,
    s.score,
    s.answercount,
    s.commentcount,
    s.quality_score,
    s.dr_quality,
    round(s.pr_views::numeric, 4) as pr_views,
    s.decile_score,
    s.close_events,
    s.reopen_events,
    s.accepted_latency,
    s.age_days,
    s.tag_count,
    s.dup_chain_depth,
    s.questions_last_year,
    s.answers_last_year,
    s.views_last_year,
    -- complex predicate to filter to interesting slice
    case when s.quality_score >= (
        select percentile_cont(0.75) within group (order by coalesce(quality_score, -1)) from rankings
    ) then true else false end as is_top_quartile_quality,
    exists (
        select 1
        from comments c
        where c.postid = s.post_id
          and c.score < 0
          and c.creationdate >= now() - interval '30 days'
    ) as has_recent_negative_comment,
    coalesce(
        (select string_agg(tg.tagname, ',' order by tg.tagname)
         from tag_explode te
         join tags tg on tg.tagname = te.tag
         where te.post_id = s.post_id),
        ''
    ) as tag_list
from stringified s
where
    -- performance-heavy mixed predicate
    (
        (s.posttypeid in (1,2) and coalesce(s.viewcount,0) > 0 and coalesce(s.score, -100) >= -10)
        or
        (s.duplicate_of_count > 0 or s.close_events > 0)
    )
    and (s.age_days <= 365.0)
    and (
        s.dr_quality <= 200
        or (s.decile_score <= 3 and s.pr_views >= 0.5)
        or (s.answers_last_year > s.questions_last_year and s.net_votes > 0)
    )
order by s.dr_quality, s.pr_views desc, s.viewcount desc
limit 500;