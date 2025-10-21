-- {"query": "38078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2039} 
with recent_users as (
    select u.id as user_id, u.displayname, u.reputation, u.creationdate
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
top_tags as (
    select t.tagname, t.count
    from tags t
    where t.count > (select percentile_disc(0.95) within group (order by count) from tags)
),
question_posts as (
    select p.id, p.owneruserid, p.creationdate, p.score, p.viewcount, p.tags
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
    select qp.id as question_id,
           qp.owneruserid,
           qp.creationdate,
           qp.score,
           qp.viewcount,
           unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as tag
    from question_posts qp
),
filtered_by_toptags as (
    select te.*
    from tag_expanded te
    join top_tags tt on tt.tagname = te.tag
),
answer_posts as (
    select p.id as answer_id, p.parentid as question_id, p.owneruserid as answerer_id, p.score as answer_score, p.creationdate as answer_creation
    from posts p
    where p.posttypeid = 2
),
first_answers as (
    select ap.question_id,
           min(ap.answer_creation) as first_answer_time
    from answer_posts ap
    group by ap.question_id
),
comments_summary as (
    select c.postid,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           sum(case when c.score < 0 then 1 else 0 end) as neg_comments
    from comments c
    group by c.postid
),
votes_summary as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_sum
    from votes v
    group by v.postid
),
accept_stats as (
    select q.id as question_id,
           case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
           q.acceptedanswerid
    from posts q
    where q.posttypeid = 1
),
dup_links as (
    select pl.postid as question_id,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
edit_events as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_time
    from posthistory ph
    group by ph.postid
),
owner_activity as (
    select p.owneruserid as owner_id,
           count(*) filter (where p.posttypeid = 1) as questions_authored,
           count(*) filter (where p.posttypeid = 2) as answers_authored,
           sum(coalesce(p.score,0)) as total_post_score
    from posts p
    group by p.owneruserid
),
gold_badge_users as (
    select b.userid, count(*) filter (where b.class = 1) as gold_badges
    from badges b
    group by b.userid
),
joined as (
    select
        fbt.question_id,
        ru.user_id,
        ru.displayname,
        ru.reputation,
        fbt.tag,
        qp.creationdate as question_creation,
        qp.score as question_score,
        qp.viewcount,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(cs.pos_comments,0) as pos_comments,
        coalesce(cs.neg_comments,0) as neg_comments,
        coalesce(vs.upvotes,0) as upvotes,
        coalesce(vs.downvotes,0) as downvotes,
        coalesce(vs.favorites,0) as favorites,
        coalesce(vs.bounty_sum,0) as bounty_sum,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(ee.edit_count,0) as edit_count,
        ee.first_edit_time,
        fa.first_answer_time,
        ac.has_accepted,
        ac.acceptedanswerid,
        oa.questions_authored,
        oa.answers_authored,
        oa.total_post_score,
        coalesce(gb.gold_badges,0) as gold_badges
    from filtered_by_toptags fbt
    join question_posts qp on qp.id = fbt.question_id
    left join recent_users ru on ru.user_id = qp.owneruserid
    left join comments_summary cs on cs.postid = fbt.question_id
    left join votes_summary vs on vs.postid = fbt.question_id
    left join dup_links dl on dl.question_id = fbt.question_id
    left join edit_events ee on ee.postid = fbt.question_id
    left join first_answers fa on fa.question_id = fbt.question_id
    left join accept_stats ac on ac.question_id = fbt.question_id
    left join owner_activity oa on oa.owner_id = qp.owneruserid
    left join gold_badge_users gb on gb.userid = qp.owneruserid
),
latency as (
    select
        j.*,
        extract(epoch from (fa.first_answer_time - j.question_creation)) as secs_to_first_answer,
        extract(epoch from (ee.first_edit_time - j.question_creation)) as secs_to_first_edit
    from joined j
    left join first_answers fa on fa.question_id = j.question_id
    left join edit_events ee on ee.postid = j.question_id
),
score_norm as (
    select
        l.*,
        (l.upvotes - l.downvotes) as net_votes,
        case when l.viewcount > 0 then (l.upvotes::numeric / l.viewcount) else 0 end as upvote_rate,
        case when l.viewcount > 0 then (l.favorites::numeric / l.viewcount) else 0 end as favorite_rate
    from latency l
),
tag_rank as (
    select
        sn.tag,
        percentile_cont(0.5) within group (order by coalesce(sn.secs_to_first_answer, 1e9)) as p50_first_answer_secs,
        percentile_cont(0.9) within group (order by coalesce(sn.secs_to_first_answer, 1e9)) as p90_first_answer_secs,
        avg(sn.net_votes) as avg_net_votes,
        avg(sn.upvote_rate) as avg_upvote_rate,
        count(*) as question_count
    from score_norm sn
    group by sn.tag
),
user_rank as (
    select
        sn.user_id,
        max(sn.displayname) as displayname,
        max(sn.reputation) as reputation,
        sum(sn.net_votes) as sum_net_votes,
        sum(sn.viewcount) as sum_views,
        sum(sn.favorites) as sum_favorites,
        avg(coalesce(sn.secs_to_first_answer, 1e9)) as avg_first_answer_secs,
        max(sn.gold_badges) as gold_badges
    from score_norm sn
    where sn.user_id is not null
    group by sn.user_id
),
heavy_rows as (
    select sn.*
    from score_norm sn
    where sn.viewcount > (select percentile_disc(0.99) within group (order by viewcount) from score_norm)
       or sn.net_votes > (select percentile_disc(0.99) within group (order by net_votes) from score_norm)
)
select
    sn.question_id,
    sn.tag,
    sn.user_id,
    sn.displayname,
    sn.reputation,
    sn.question_creation,
    sn.viewcount,
    sn.question_score,
    sn.upvotes,
    sn.downvotes,
    sn.net_votes,
    sn.favorites,
    sn.favorite_rate,
    sn.upvote_rate,
    sn.comment_count,
    sn.duplicate_links,
    sn.edit_count,
    sn.secs_to_first_answer,
    sn.secs_to_first_edit,
    sn.has_accepted,
    tr.p50_first_answer_secs,
    tr.p90_first_answer_secs,
    tr.avg_net_votes,
    tr.avg_upvote_rate,
    ur.sum_net_votes as user_sum_net_votes,
    ur.sum_views as user_sum_views,
    ur.sum_favorites as user_sum_favorites,
    ur.avg_first_answer_secs as user_avg_first_answer_secs,
    ur.gold_badges as user_gold_badges,
    case when sn.question_id in (select question_id from heavy_rows) then true else false end as is_heavy_row
from score_norm sn
join tag_rank tr on tr.tag = sn.tag
left join user_rank ur on ur.user_id = sn.user_id
where sn.question_creation >= (select max(creationdate) - interval '180 days' from posts)
order by tr.p50_first_answer_secs asc nulls last, sn.net_votes desc, sn.viewcount desc
limit 500;