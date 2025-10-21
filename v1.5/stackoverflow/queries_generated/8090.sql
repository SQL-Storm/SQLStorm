-- {"query": "8090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3215} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from users)
),
questions as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        (string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag_arr
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts where posttypeid = 1)
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
      and a.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts where posttypeid = 2)
),
first_answer as (
    select
        q.question_id,
        min(a.a_created) as first_answer_time
    from questions q
    left join answers a on a.question_id = q.question_id
    group by q.question_id
),
question_stats as (
    select
        q.question_id,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.viewcount,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.tag_arr,
        fa.first_answer_time,
        extract(epoch from (fa.first_answer_time - q.q_created))::bigint as seconds_to_first_answer,
        count(a.answer_id) as answer_count,
        sum(case when a.answer_id = q.acceptedanswerid then 1 else 0 end) as has_accepted,
        avg(a.a_score)::numeric(18,4) as avg_answer_score,
        sum(case when a.a_score > 0 then 1 else 0 end) as positive_answers
    from questions q
    left join answers a on a.question_id = q.question_id
    left join first_answer fa on fa.question_id = q.question_id
    group by q.question_id, q.asker_id, q.q_created, q.q_score, q.viewcount, q.title, q.tags, q.acceptedanswerid, q.tag_arr, fa.first_answer_time
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        avg(c.score)::numeric(18,4) as avg_comment_score,
        sum(case when c.score < 0 then 1 else 0 end) as negative_comments
    from comments c
    where c.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from comments)
    group by c.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes,
        sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes,
        sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites,
        sum(case when vt.name = 'BountyStart' or vt.name = 'BountyClose' then coalesce(v.bountyamount,0) else 0 end) as bounty_amount
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    where v.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from votes)
    group by v.postid
),
edits as (
    select
        ph.postid,
        count(*) filter (where pht.name in ('Edit Title','Edit Body','Edit Tags')) as edit_count,
        max(ph.creationdate) filter (where pht.name in ('Edit Title','Edit Body','Edit Tags')) as last_edit_date,
        count(*) filter (where pht.name = 'Post Closed') as close_events,
        count(*) filter (where pht.name = 'Post Reopened') as reopen_events
    from posthistory ph
    join posthistorytypes pht on pht.id = ph.posthistorytypeid
    where ph.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posthistory)
    group by ph.postid
),
duplicates as (
    select
        pl.postid as dup_question_id,
        count(*) filter (where lt.name = 'Duplicate') as dup_links,
        bool_or(lt.name = 'Duplicate') as is_marked_duplicate
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where pl.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from postlinks)
    group by pl.postid
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= (select coalesce(max(date), now()) - interval '3 years' from badges)
    group by b.userid
),
tag_exploded as (
    select
        qs.question_id,
        lower(trim(t)) as tagname
    from question_stats qs
    cross join lateral unnest(qs.tag_arr) as t
),
tag_meta as (
    select
        te.question_id,
        te.tagname,
        tg.count as global_tag_count,
        coalesce(nullif(tg.tagname, ''), te.tagname) as tagname_norm
    from tag_exploded te
    left join tags tg on lower(tg.tagname) = lower(te.tagname)
),
ranked_questions as (
    select
        qs.*,
        coalesce(c.comment_count, 0) as comment_count,
        coalesce(c.avg_comment_score, 0) as avg_comment_score,
        coalesce(c.negative_comments, 0) as negative_comments,
        coalesce(v.upvotes, 0) as upvotes,
        coalesce(v.downvotes, 0) as downvotes,
        coalesce(v.favorites, 0) as favorites,
        coalesce(v.bounty_amount, 0) as bounty_amount,
        coalesce(e.edit_count, 0) as edit_count,
        e.last_edit_date,
        coalesce(e.close_events, 0) as close_events,
        coalesce(e.reopen_events, 0) as reopen_events,
        coalesce(d.dup_links, 0) as dup_links,
        coalesce(d.is_marked_duplicate, false) as is_marked_duplicate,
        row_number() over (partition by qs.asker_id order by qs.q_score desc nulls last, qs.viewcount desc nulls last, qs.q_created desc) as rn_asker_top,
        percentile_cont(0.5) within group (order by coalesce(qs.seconds_to_first_answer, 86400)) over () as median_time_to_first_answer
    from question_stats qs
    left join comment_stats c on c.postid = qs.question_id
    left join vote_agg v on v.postid = qs.question_id
    left join edits e on e.postid = qs.question_id
    left join duplicates d on d.dup_question_id = qs.question_id
),
user_activity as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.cohort_month,
        u.location,
        ua.total_badges,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.last_badge_date,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_authored,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_authored,
        sum(coalesce(p.score,0)) as total_post_score,
        max(p.creationdate) as last_post_date
    from recent_users u
    left join posts p on p.owneruserid = u.user_id and p.creationdate >= u.creationdate
    left join user_badges ua on ua.userid = u.user_id
    group by u.user_id, u.displayname, u.reputation, u.cohort_month, u.location, ua.total_badges, ua.gold_badges, ua.silver_badges, ua.bronze_badges, ua.last_badge_date
),
acceptance_cte as (
    select
        q.asker_id,
        count(*) filter (where qs.has_accepted > 0) as accepted_questions,
        count(*) as total_questions
    from question_stats qs
    join questions q on q.question_id = qs.question_id
    group by q.asker_id
),
question_quality as (
    select
        rq.question_id,
        rq.asker_id,
        rq.q_created,
        rq.q_score,
        rq.viewcount,
        rq.answer_count,
        rq.has_accepted,
        rq.seconds_to_first_answer,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.bounty_amount,
        rq.edit_count,
        rq.dup_links,
        rq.is_marked_duplicate,
        rq.comment_count,
        rq.avg_comment_score,
        rq.negative_comments,
        1.0 * coalesce(rq.q_score,0)
          + 0.1 * coalesce(rq.viewcount,0)
          + 2.0 * coalesce(rq.upvotes,0)
          - 3.0 * coalesce(rq.downvotes,0)
          + 5.0 * case when rq.has_accepted > 0 then 1 else 0 end
          + 0.5 * coalesce(rq.answer_count,0)
          - 0.001 * coalesce(rq.seconds_to_first_answer, 86400)
          - 2.0 * case when rq.is_marked_duplicate then 1 else 0 end
          - 0.5 * coalesce(rq.negative_comments,0)
          + 0.2 * coalesce(rq.favorites,0)
          + 0.0005 * coalesce(rq.bounty_amount,0)
          - 0.1 * coalesce(rq.edit_count,0)
        as quality_score,
        rq.rn_asker_top,
        rq.median_time_to_first_answer
    from ranked_questions rq
),
top_user_questions as (
    select
        qq.*,
        row_number() over (partition by qq.asker_id order by qq.quality_score desc nulls last, qq.q_created desc) as rn_quality
    from question_quality qq
),
tag_agg as (
    select
        tm.tagname_norm,
        count(distinct tm.question_id) as questions_with_tag,
        avg(qq.quality_score)::numeric(18,4) as avg_quality_for_tag
    from tag_meta tm
    join question_quality qq on qq.question_id = tm.question_id
    group by tm.tagname_norm
),
final_users as (
    select
        ua.*,
        ac.accepted_questions,
        ac.total_questions,
        case when ac.total_questions > 0 then round(100.0 * ac.accepted_questions / ac.total_questions, 2) else 0 end as accept_rate_pct
    from user_activity ua
    left join acceptance_cte ac on ac.asker_id = ua.user_id
),
user_rank as (
    select
        fu.*,
        dense_rank() over (order by coalesce(fu.reputation,0) desc, coalesce(fu.total_post_score,0) desc) as rep_rank,
        dense_rank() over (order by coalesce(fu.accept_rate_pct,0) desc) as accept_rank
    from final_users fu
)
select
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.location,
    to_char(ur.cohort_month, 'YYYY-MM') as cohort_month,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.questions_authored,
    ur.answers_authored,
    ur.total_post_score,
    ur.accept_rate_pct,
    ur.rep_rank,
    ur.accept_rank,
    tq.question_id as top_question_id,
    tq.q_created as top_question_created,
    tq.q_score as top_question_score,
    tq.viewcount as top_question_views,
    tq.answer_count as top_question_answers,
    tq.has_accepted as top_question_has_accepted,
    tq.seconds_to_first_answer,
    tq.quality_score as top_question_quality_score,
    tq.median_time_to_first_answer as global_median_t_first_answer_seconds,
    coalesce(string_agg(distinct tm.tagname_norm, ',' order by tm.tagname_norm) filter (where tq.question_id = tm.question_id), '') as top_question_tags,
    coalesce(ta.avg_quality_for_tag, 0)::numeric(18,4) as avg_quality_for_primary_tag
from user_rank ur
left join top_user_questions tq on tq.asker_id = ur.user_id and tq.rn_quality = 1
left join tag_meta tm on tm.question_id = tq.question_id
left join lateral (
    select ta.avg_quality_for_tag
    from tag_agg ta
    join tag_meta tmx on tmx.tagname_norm = ta.tagname_norm
    where tmx.question_id = tq.question_id
    order by ta.avg_quality_for_tag desc nulls last
    limit 1
) ta on true
where (ur.rep_rank <= 100 or ur.accept_rank <= 100)
group by
    ur.user_id, ur.displayname, ur.reputation, ur.location, ur.cohort_month,
    ur.total_badges, ur.gold_badges, ur.silver_badges, ur.bronze_badges,
    ur.questions_authored, ur.answers_authored, ur.total_post_score, ur.accept_rate_pct,
    ur.rep_rank, ur.accept_rank,
    tq.question_id, tq.q_created, tq.q_score, tq.viewcount, tq.answer_count, tq.has_accepted,
    tq.seconds_to_first_answer, tq.quality_score, tq.median_time_to_first_answer,
    ta.avg_quality_for_tag
order by ur.rep_rank, ur.accept_rank, ur.user_id;