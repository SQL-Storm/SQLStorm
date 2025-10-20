-- {"query": "8098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3309} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as host,
        row_number() over (partition by coalesce(u.location, 'UNKNOWN') order by u.reputation desc, u.id) as rn_loc,
        rank() over (order by u.reputation desc) as rep_rank
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
user_badge_summary as (
    select
        b.userid,
        count(*) as badge_count,
        sum((b.class = 1)::int) as gold_count,
        sum((b.class = 2)::int) as silver_count,
        sum((b.class = 3)::int) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.closeddate,
        p.acceptedanswerid,
        (p.closeddate is not null)::int as is_closed
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select
        p.id as answer_id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate as answer_date,
        p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
first_answers as (
    select
        ap.question_id,
        min(ap.answer_date) as first_answer_date
    from a_posts ap
    group by ap.question_id
),
accept_times as (
    select
        qp.post_id,
        qp.acceptedanswerid,
        min(ph.creationdate) as accepted_on
    from q_posts qp
    left join posthistory ph
        on ph.postid = qp.post_id
       and ph.posthistorytypeid in (1,2,3,4,5,6,7,8,9,24) -- edits as proxy for activity
    group by qp.post_id, qp.acceptedanswerid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) as total_votes
    from votes v
    where v.creationdate >= (select coalesce(min(creationdate), now() - interval '10 years') from posts)
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        avg(nullif(c.score,0)) as avg_comment_score_nonzero,
        sum((c.userdisplayname is null and c.userid is null)::int) as anon_comments
    from comments c
    group by c.postid
),
tag_expanded as (
    select
        qp.post_id,
        unnest(string_to_array(substring(coalesce(qp.tags, ''), 2, greatest(length(coalesce(qp.tags, ''))-2,0)), '><')) as tagname
    from q_posts qp
),
tag_quality as (
    select
        te.tagname,
        count(*) as q_count,
        avg(qp.score::numeric) as avg_q_score,
        avg(qp.viewcount::numeric) as avg_q_views,
        sum(qp.answercount) as total_answers
    from tag_expanded te
    join q_posts qp on qp.post_id = te.post_id
    group by te.tagname
),
dupe_links as (
    select
        pl.postid as duplicate_of,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
user_activity as (
    select
        ru.user_id,
        count(distinct qp.post_id) as questions,
        count(distinct ap.answer_id) as answers,
        avg(coalesce(qp.score,0)::numeric) as avg_q_score,
        avg(coalesce(ap.answer_score,0)::numeric) as avg_a_score,
        sum(coalesce(vq.upvotes,0) + coalesce(va.upvotes,0)) as upvotes_given_to_posts,
        sum(coalesce(vq.downvotes,0) + coalesce(va.downvotes,0)) as downvotes_given_to_posts,
        max(coalesce(qp.creationdate, ap.answer_date)) as last_post_date
    from recent_users ru
    left join q_posts qp on qp.user_id = ru.user_id
    left join a_posts ap on ap.user_id = ru.user_id
    left join votes_agg vq on vq.postid = qp.post_id
    left join votes_agg va on va.postid = ap.answer_id
    group by ru.user_id
),
accepted_latency as (
    select
        qp.post_id,
        qp.user_id,
        qp.creationdate as q_date,
        fa.first_answer_date,
        case
            when qp.acceptedanswerid is null then null
            else greatest(fa.first_answer_date, qp.creationdate)
        end as first_response_date,
        case when qp.acceptedanswerid is null then null else at.accepted_on end as accepted_on
    from q_posts qp
    left join first_answers fa on fa.question_id = qp.post_id
    left join accept_times at on at.post_id = qp.post_id
),
user_latency as (
    select
        al.user_id,
        percentile_cont(0.5) within group (order by extract(epoch from (al.first_response_date - al.q_date))) as p50_first_response_secs,
        percentile_cont(0.9) within group (order by extract(epoch from (al.first_response_date - al.q_date))) as p90_first_response_secs,
        percentile_cont(0.5) within group (order by extract(epoch from (al.accepted_on - al.q_date))) as p50_accept_secs,
        count(*) filter (where al.accepted_on is not null) as accepted_questions,
        count(*) as total_questions_for_latency
    from accepted_latency al
    where al.first_response_date is not null
    group by al.user_id
),
power_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.host,
        coalesce(ubs.badge_count,0) as badges,
        coalesce(ubs.gold_count,0) as gold,
        coalesce(ubs.silver_count,0) as silver,
        coalesce(ubs.bronze_count,0) as bronze,
        ua.questions,
        ua.answers,
        ua.avg_q_score,
        ua.avg_a_score,
        ua.upvotes_given_to_posts,
        ua.downvotes_given_to_posts,
        ul.p50_first_response_secs,
        ul.p90_first_response_secs,
        ul.p50_accept_secs,
        ul.accepted_questions,
        ru.rep_rank,
        ru.rn_loc
    from recent_users ru
    left join user_badge_summary ubs on ubs.userid = ru.user_id
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_latency ul on ul.user_id = ru.user_id
),
question_quality as (
    select
        qp.post_id,
        qp.user_id,
        qp.title,
        qp.creationdate,
        qp.score,
        qp.viewcount,
        qp.answercount,
        qp.closeddate,
        coalesce(vq.upvotes,0) as upvotes,
        coalesce(vq.downvotes,0) as downvotes,
        coalesce(vq.favorites,0) as favorites,
        coalesce(vq.bounty_total,0) as bounty_total,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.anon_comments,0) as anon_comments,
        coalesce(du.dup_count,0) as dup_links,
        coalesce(du.linked_count,0) as linked_links,
        case when qp.closeddate is null then 1 else 0 end as is_open,
        case when qp.answercount > 0 then 1 else 0 end as has_answers
    from q_posts qp
    left join votes_agg vq on vq.postid = qp.post_id
    left join comments_agg ca on ca.postid = qp.post_id
    left join dupe_links du on du.duplicate_of = qp.post_id
),
top_tags as (
    select
        tq.tagname,
        tq.q_count,
        tq.avg_q_score,
        tq.avg_q_views,
        row_number() over (order by tq.q_count desc, tq.avg_q_score desc) as rn
    from tag_quality tq
),
recent_hot_questions as (
    select
        qq.post_id,
        qq.user_id,
        qq.title,
        qq.creationdate,
        qq.score,
        qq.viewcount,
        qq.answercount,
        qq.upvotes,
        qq.downvotes,
        qq.favorites,
        qq.bounty_total,
        qq.comment_count,
        qq.dup_links,
        qq.linked_links,
        qq.is_open,
        qq.has_answers,
        dense_rank() over (order by (qq.upvotes - qq.downvotes) desc, qq.viewcount desc, qq.favorites desc) as hot_rank
    from question_quality qq
    where qq.creationdate >= (select max(creationdate) - interval '180 days' from posts)
),
final_users as (
    select
        pu.*,
        case
            when pu.reputation >= 100000 then 'legend'
            when pu.reputation >= 50000 then 'elite'
            when pu.reputation >= 10000 then 'pro'
            when pu.reputation >= 1000 then 'rising'
            else 'newbie'
        end as tier
    from power_users pu
),
cross_user_pairs as (
    select
        fu1.user_id as user_a,
        fu2.user_id as user_b,
        abs(coalesce(fu1.reputation,0) - coalesce(fu2.reputation,0)) as rep_gap,
        (coalesce(fu1.location,'') = coalesce(fu2.location,''))::int as same_location
    from final_users fu1
    join final_users fu2 on fu1.user_id < fu2.user_id
    where fu1.tier in ('elite','legend') and fu2.tier in ('pro','elite','legend')
),
tag_focus as (
    select
        te.tagname,
        qp.user_id,
        count(*) as tag_qs,
        avg(qp.score::numeric) as tag_avg_score
    from tag_expanded te
    join q_posts qp on qp.post_id = te.post_id
    group by te.tagname, qp.user_id
),
user_tag_rank as (
    select
        tf.user_id,
        tf.tagname,
        tf.tag_qs,
        tf.tag_avg_score,
        row_number() over (partition by tf.user_id order by tf.tag_qs desc, tf.tag_avg_score desc, tf.tagname) as rn
    from tag_focus tf
),
user_top3_tags as (
    select
        utr.user_id,
        string_agg(utr.tagname || ':' || tfmt.tag_qs::text || '/' || round(coalesce(utr.tag_avg_score,0),2)::text, ', ' order by utr.rn) as top_tags
    from user_tag_rank utr
    left join lateral (select utr.tag_qs) tfmt on true
    where utr.rn <= 3
    group by utr.user_id
),
zero_answer_orphan as (
    select
        qp.post_id,
        qp.creationdate,
        (select count(*) from a_posts ap where ap.question_id = qp.post_id) as answers_now,
        (select max(c.creationdate) from comments c where c.postid = qp.post_id) as last_comment_date
    from q_posts qp
    where qp.answercount = 0 and qp.closeddate is null
),
set_op as (
    select post_id from recent_hot_questions where hot_rank <= 200
    union
    select post_id from question_quality where favorites >= 10
    except
    select post_id from question_quality where is_open = 0
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.location,
    fu.host,
    fu.tier,
    fu.questions,
    fu.answers,
    coalesce(ut3.top_tags, '(none)') as top_tags,
    coalesce(fu.p50_first_response_secs, -1) as p50_first_response_secs,
    coalesce(fu.p90_first_response_secs, -1) as p90_first_response_secs,
    coalesce(fu.p50_accept_secs, -1) as p50_accept_secs,
    fu.accepted_questions,
    fu.avg_q_score,
    fu.avg_a_score,
    qq.post_id as sample_post_id,
    qq.title as sample_title,
    qq.score as sample_score,
    qq.viewcount as sample_views,
    qq.answercount as sample_answers,
    qq.upvotes,
    qq.downvotes,
    qq.favorites,
    qq.bounty_total,
    qq.comment_count,
    qq.dup_links,
    qq.linked_links,
    th.hot_rank,
    tt.tagname as top_tag_by_volume,
    tt.q_count as top_tag_count,
    tt.avg_q_score as top_tag_avg_score,
    coalesce(zo.answers_now, 0) as current_answers_for_orphan,
    case
        when zo.last_comment_date is null then 'never discussed'
        when zo.last_comment_date < now() - interval '365 days' then 'stale'
        else 'active'
    end as orphan_discussion_state,
    cup.rep_gap as elite_proximity_gap,
    cup.same_location as elite_same_location
from final_users fu
left join user_top3_tags ut3 on ut3.user_id = fu.user_id
left join lateral (
    select qq2.*
    from question_quality qq2
    where qq2.user_id = fu.user_id
    order by (qq2.upvotes - qq2.downvotes) desc, qq2.viewcount desc, qq2.favorites desc, qq2.post_id
    limit 1
) qq on true
left join recent_hot_questions th on th.post_id = qq.post_id
left join top_tags tt on tt.rn = 1
left join zero_answer_orphan zo on zo.post_id = qq.post_id
left join cross_user_pairs cup on (cup.user_a = fu.user_id and fu.tier in ('elite','legend'))
where fu.rep_rank <= 200
  and (qq.post_id in (select post_id from set_op) or qq.post_id is null)
order by fu.rep_rank, fu.user_id
limit 150;