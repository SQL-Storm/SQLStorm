with recursive recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           u.upvotes,
           u.downvotes,
           row_number() over (order by u.creationdate desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
top_recent_users as (
    select ru.*
    from recent_users ru
    where ru.rn <= 1000
),
q_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.favoritecount,
           p.commentcount,
           p.tags,
           p.title,
           p.closeddate,
           coalesce(nullif(trim(p.ownerdisplayname), ''), 'unknown') as ownerdisplayname_norm
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select p.id as post_id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
user_q as (
    select q.*
    from q_posts q
    join top_recent_users u on u.user_id = q.user_id
),
user_a as (
    select a.*
    from a_posts a
    join top_recent_users u on u.user_id = a.user_id
),
tag_expanded as (
    select q.post_id,
           unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from user_q q
    where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
    select te.tag,
           count(*) as tag_q_count,
           avg(cast(q.score as numeric)) as tag_q_avgscore,
           sum(q.viewcount) as tag_q_views
    from tag_expanded te
    join user_q q on q.post_id = te.post_id
    group by te.tag
),
user_activity as (
    select u.user_id,
           sum(case when q.post_id is not null then 1 else 0 end) as questions,
           sum(coalesce(q.viewcount,0)) as question_views,
           avg(q.score) filter (where q.score is not null and q.score <> 0) as avg_q_score_nonzero,
           sum(case when a.post_id is not null then 1 else 0 end) as answers,
           avg(a.score) as avg_a_score,
           count(distinct te.tag) as distinct_tags,
           max(q.closeddate) as last_closeddate
    from top_recent_users u
    left join user_q q on q.user_id = u.user_id
    left join user_a a on a.user_id = u.user_id
    left join tag_expanded te on te.post_id = q.post_id
    group by u.user_id
),
last_activity as (
    select p.owneruserid as user_id,
           max(p.lastactivitydate) as last_activity_date
    from posts p
    where p.owneruserid in (select user_id from top_recent_users)
    group by p.owneruserid
),
dup_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as canonical_post_id,
           pl.creationdate as dup_marked_date
    from postlinks pl
    where pl.linktypeid = 3
),
close_events as (
    select ph.postid,
           ph.creationdate as closed_at,
           ph.comment as close_reason_id,
           case
             when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer)
             else null
           end as close_reason_int
    from posthistory ph
    where ph.posthistorytypeid = 10
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           count(*) as total_votes
    from votes v
    where v.postid in (select post_id from user_q union select post_id from user_a)
    group by v.postid
),
comment_sentiment as (
    select c.postid,
           avg(length(c.text)) as avg_comment_len,
           sum(case when position('thank' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count,
           sum(case when position('bug' in lower(c.text)) > 0 then 1 else 0 end) as bug_count,
           count(*) as comment_count
    from comments c
    where c.postid in (select post_id from user_q union select post_id from user_a)
    group by c.postid
),
post_quality as (
    select q.post_id,
           q.user_id,
           q.score,
           q.viewcount,
           coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as vote_balance,
           coalesce(va.total_votes,0) as total_votes,
           coalesce(cs.avg_comment_len,0) as avg_comment_len,
           coalesce(cs.thanks_count,0) as thanks_count,
           coalesce(cs.bug_count,0) as bug_count,
           case when q.viewcount > 0 then (cast(q.score as numeric) / greatest(q.viewcount,1)) else 0 end as score_per_view,
           case when coalesce(va.total_votes,0) > 0 then cast(q.score as numeric) / va.total_votes else null end as score_per_vote,
           case when q.closeddate is not null then 1 else 0 end as is_closed,
           case when exists (select 1 from dup_links d where d.dup_post_id = q.post_id) then 1 else 0 end as is_duplicate
    from user_q q
    left join vote_agg va on va.postid = q.post_id
    left join comment_sentiment cs on cs.postid = q.post_id
),
user_badges as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
           count(*) as total_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    where b.userid in (select user_id from top_recent_users)
    group by b.userid
),
user_top_tags as (
    select te.tag,
           q.user_id,
           count(*) as cnt,
           row_number() over (partition by q.user_id order by count(*) desc, te.tag) as rn
    from user_q q
    join tag_expanded te on te.post_id = q.post_id
    group by q.user_id, te.tag
),
user_tag_pivot as (
    select utt.user_id,
           max(case when utt.rn = 1 then utt.tag end) as top_tag_1,
           max(case when utt.rn = 2 then utt.tag end) as top_tag_2,
           max(case when utt.rn = 3 then utt.tag end) as top_tag_3
    from user_top_tags utt
    where utt.rn <= 3
    group by utt.user_id
),
user_post_quality_agg as (
    select pq.user_id,
           avg(pq.score) as avg_q_score,
           avg(pq.score_per_view) as avg_score_per_view,
           avg(nullif(pq.score_per_vote,0)) as avg_score_per_vote_nonzero,
           sum(case when pq.is_closed = 1 then 1 else 0 end) as closed_q,
           sum(case when pq.is_duplicate = 1 then 1 else 0 end) as duplicate_q,
           sum(pq.vote_balance) as sum_vote_balance,
           sum(pq.total_votes) as sum_total_votes,
           avg(pq.avg_comment_len) as avg_comment_len_over_q,
           sum(pq.thanks_count) as sum_thanks_comments,
           sum(pq.bug_count) as sum_bug_comments
    from post_quality pq
    group by pq.user_id
),
answer_quality as (
    select a.post_id,
           a.user_id,
           a.score,
           coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as vote_balance,
           coalesce(va.total_votes,0) as total_votes,
           coalesce(cs.comment_count,0) as comment_count
    from user_a a
    left join vote_agg va on va.postid = a.post_id
    left join comment_sentiment cs on cs.postid = a.post_id
),
user_answer_quality_agg as (
    select aq.user_id,
           avg(aq.score) as avg_a_score,
           sum(aq.vote_balance) as sum_a_vote_balance,
           sum(aq.total_votes) as sum_a_total_votes,
           avg(aq.comment_count) as avg_a_comment_count
    from answer_quality aq
    group by aq.user_id
),
user_rank as (
    select u.user_id,
           dense_rank() over (order by
                coalesce(u.reputation,0) desc,
                coalesce(ua.answers,0) desc,
                coalesce(ua.questions,0) desc
           ) as rep_activity_rank
    from top_recent_users u
    left join user_activity ua on ua.user_id = u.user_id
),
user_summary as (
    select u.user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.upvotes,
           u.downvotes,
           ua.questions,
           ua.answers,
           ua.distinct_tags,
           ua.question_views,
           ua.avg_q_score_nonzero,
           ua.last_closeddate,
           la.last_activity_date,
           ub.gold, ub.silver, ub.bronze, ub.tag_badges, ub.total_badges,
           ub.first_badge_date, ub.last_badge_date,
           utp.top_tag_1, utp.top_tag_2, utp.top_tag_3,
           upq.avg_q_score, upq.avg_score_per_view, upq.avg_score_per_vote_nonzero,
           upq.closed_q, upq.duplicate_q, upq.sum_vote_balance, upq.sum_total_votes,
           upq.avg_comment_len_over_q, upq.sum_thanks_comments, upq.sum_bug_comments,
           uaq.avg_a_score, uaq.sum_a_vote_balance, uaq.sum_a_total_votes, uaq.avg_a_comment_count,
           ur.rep_activity_rank
    from top_recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join last_activity la on la.user_id = u.user_id
    left join user_badges ub on ub.user_id = u.user_id
    left join user_tag_pivot utp on utp.user_id = u.user_id
    left join user_post_quality_agg upq on upq.user_id = u.user_id
    left join user_answer_quality_agg uaq on uaq.user_id = u.user_id
    left join user_rank ur on ur.user_id = u.user_id
),
closed_reason_lookup as (
    select crt.id as reason_id,
           crt.name as reason_name
    from closereasontypes crt
),
closed_questions as (
    select q.post_id,
           q.user_id,
           ce.closed_at,
           ce.close_reason_int,
           cr.reason_name
    from user_q q
    join close_events ce on ce.postid = q.post_id
    left join closed_reason_lookup cr on cr.reason_id = ce.close_reason_int
),
dup_chain as (
    select d.dup_post_id,
           d.canonical_post_id,
           1 as depth
    from dup_links d
    union all
    select d.dup_post_id,
           d.canonical_post_id,
           dc.depth + 1
    from dup_links d
    join dup_chain dc on d.dup_post_id = dc.canonical_post_id
),
dup_resolved as (
    select dup_post_id,
           max(canonical_post_id) filter (where depth = (select max(depth) from dup_chain d2 where d2.dup_post_id = dup_chain.dup_post_id)) as ultimate_canonical
    from dup_chain
    group by dup_post_id
),
final as (
    select
        us.user_id,
        us.displayname,
        coalesce(nullif(trim(us.location), ''), 'N/A') as location_norm,
        us.reputation,
        us.upvotes - us.downvotes as net_votes,
        us.questions,
        us.answers,
        us.distinct_tags,
        us.question_views,
        us.avg_q_score_nonzero,
        us.avg_q_score,
        us.avg_score_per_view,
        us.avg_score_per_vote_nonzero,
        us.closed_q,
        us.duplicate_q,
        us.sum_vote_balance,
        us.sum_total_votes,
        us.avg_comment_len_over_q,
        us.sum_thanks_comments,
        us.sum_bug_comments,
        us.avg_a_score,
        us.sum_a_vote_balance,
        us.sum_a_total_votes,
        us.avg_a_comment_count,
        us.gold, us.silver, us.bronze, us.tag_badges, us.total_badges,
        us.top_tag_1, us.top_tag_2, us.top_tag_3,
        us.first_badge_date, us.last_badge_date,
        us.last_closeddate,
        us.last_activity_date,
        us.rep_activity_rank,
        case
            when coalesce(us.answers,0) = 0 then null
            else (cast(coalesce(us.sum_a_vote_balance,0) as numeric) / greatest(us.answers,1))
        end as avg_answer_vote_balance,
        case
            when coalesce(us.questions,0) = 0 then null
            else (cast(coalesce(us.sum_vote_balance,0) as numeric) / greatest(us.questions,1))
        end as avg_question_vote_balance
    from user_summary us
)
select
    f.*,
    count(distinct cq.post_id) as closed_posts,
    count(distinct dr.dup_post_id) as dup_posts_with_chain,
    min(cq.closed_at) as first_time_closed,
    max(cq.closed_at) as last_time_closed,
    string_agg(distinct coalesce(cq.reason_name, 'Unknown'), ', ' order by coalesce(cq.reason_name, 'Unknown')) as close_reasons_summary
from final f
left join closed_questions cq on cq.user_id = f.user_id
left join dup_resolved dr on dr.dup_post_id in (
    select q.post_id from user_q q where q.user_id = f.user_id
)
group by
    f.user_id, f.displayname, f.location_norm, f.reputation, f.net_votes,
    f.questions, f.answers, f.distinct_tags, f.question_views, f.avg_q_score_nonzero,
    f.avg_q_score, f.avg_score_per_view, f.avg_score_per_vote_nonzero, f.closed_q, f.duplicate_q,
    f.sum_vote_balance, f.sum_total_votes, f.avg_comment_len_over_q, f.sum_thanks_comments, f.sum_bug_comments,
    f.avg_a_score, f.sum_a_vote_balance, f.sum_a_total_votes, f.avg_a_comment_count,
    f.gold, f.silver, f.bronze, f.tag_badges, f.total_badges, f.top_tag_1, f.top_tag_2, f.top_tag_3,
    f.first_badge_date, f.last_badge_date, f.last_closeddate, f.last_activity_date, f.rep_activity_rank,
    f.avg_answer_vote_balance, f.avg_question_vote_balance
having
    coalesce(f.answers,0) + coalesce(f.questions,0) > 0
order by
    f.rep_activity_rank,
    coalesce(f.sum_a_total_votes + f.sum_total_votes, 0) desc,
    f.user_id
limit 200;