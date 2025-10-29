-- {"query": "499.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3235}
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.user_id as ownernull_user_id,
        p.owneruserid,
        p.acceptedanswerid,
        p.parentid,
        p.title,
        p.tags,
        coalesce(p.lastactivitydate, p.creationdate) as last_activity,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from (
        select
            p.*,
            nullif(p.owneruserid, -1) as user_id
        from posts p
        where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    ) p
),
user_activity as (
    select
        u.id as user_id,
        u.reputation,
        u.creationdate as user_creation,
        u.location,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        count(distinct ph.id) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
        count(distinct c.id) as comment_events,
        count(distinct b.id) as badge_events,
        count(distinct v.id) filter (where v.votetypeid in (2,3)) as cast_votes,
        max(least(u.lastaccessdate, timestamp '2024-10-01 12:34:56')) as last_access
    from users u
    left join posthistory ph on ph.userid = u.id and ph.creationdate >= timestamp '2024-10-01 12:34:56' - interval '365 days'
    left join comments c on c.userid = u.id and c.creationdate >= timestamp '2024-10-01 12:34:56' - interval '365 days'
    left join badges b on b.userid = u.id and b.date >= timestamp '2024-10-01 12:34:56' - interval '365 days'
    left join votes v on v.userid = u.id and v.creationdate >= timestamp '2024-10-01 12:34:56' - interval '365 days'
    group by u.id, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.views
),
question_metrics as (
    select
        q.id as question_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.owneruserid as owner_user_id,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.commentcount,
        q.favoritecount,
        q.answercount,
        q.closeddate,
        q.communityowneddate,
        array_length(string_to_array(coalesce(substring(q.tags, 2, greatest(length(q.tags)-2,0)), ''), '><'), 1) as tag_count,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
        count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_of_count,
        count(distinct pl2.postid) filter (where pl2.linktypeid = 3) as has_duplicates_count
    from posts q
    left join votes v on v.postid = q.id and v.creationdate >= q.creationdate and v.creationdate < q.creationdate + interval '365 days'
    left join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
    left join postlinks pl2 on pl2.relatedpostid = q.id and pl2.linktypeid = 3
    where q.posttypeid = 1
      and q.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
    group by q.id, q.creationdate, q.score, q.viewcount, q.owneruserid, q.title, q.tags, q.acceptedanswerid, q.commentcount, q.favoritecount, q.answercount, q.closeddate, q.communityowneddate
),
answer_metrics as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.creationdate,
        a.score,
        a.owneruserid as owner_user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        max(case when a.id = q.acceptedanswerid then 1 else 0 end) as is_accepted
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    left join votes v on v.postid = a.id
    where a.posttypeid = 2
      and a.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 2)
    group by a.id, a.parentid, a.creationdate, a.score, a.owneruserid
),
answer_rank as (
    select
        am.*,
        row_number() over (partition by am.question_id order by am.is_accepted desc, am.score desc, am.upvotes - am.downvotes desc, am.creationdate asc) as rn,
        rank() over (partition by am.owner_user_id order by am.score desc NULLS LAST) as user_answer_rank
    from answer_metrics am
),
hotness as (
    select
        qm.question_id,
        qm.creationdate,
        qm.score,
        qm.viewcount,
        qm.answercount,
        qm.commentcount,
        qm.upvotes,
        qm.downvotes,
        qm.favoritecount,
        qm.favorites_legacy,
        extract(epoch from (timestamp '2024-10-01 12:34:56' - qm.creationdate)) / 3600.0 as age_hours,
        (coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0)) * 2
          + coalesce(qm.viewcount,0) * 0.001
          + coalesce(qm.answercount,0) * 3
          + coalesce(qm.commentcount,0) * 1.2
          + coalesce(qm.favoritecount,0) * 1.5
          + coalesce(qm.favorites_legacy,0) * 0.8
          - case when qm.closeddate is not null then 10 else 0 end
          - ln(greatest(extract(epoch from (timestamp '2024-10-01 12:34:56' - qm.creationdate)) / 3600.0 + 2, 2)) * 5
          as hot_score_raw
    from question_metrics qm
),
hotness_norm as (
    select
        h.*,
        (h.hot_score_raw - avg(h.hot_score_raw) over ()) / nullif(stddev_pop(h.hot_score_raw) over (),0) as hot_score_z
    from hotness h
),
tag_explode as (
    select
        qm.question_id,
        unnest(string_to_array(coalesce(substring(qm.tags, 2, greatest(length(qm.tags)-2,0)), ''), '><')) as tag
    from question_metrics qm
),
tag_stats as (
    select
        te.tag,
        count(*) as q_count,
        sum(case when h.hot_score_z > 1 then 1 else 0 end) as hot_q_count,
        avg(h.hot_score_z) as avg_hot_z
    from tag_explode te
    join hotness_norm h on h.question_id = te.question_id
    group by te.tag
    having count(*) >= 5
),
dupe_chains as (
    select
        q.question_id,
        count(*) filter (where qm.duplicate_of_count > 0 or qm.has_duplicates_count > 0) over (partition by q.question_id) as dupe_involved
    from question_metrics qm
    join question_metrics q on q.question_id = qm.question_id
),
edits_and_closures as (
    select
        ph.postid as question_id,
        sum(case when ph.posthistorytypeid in (4,5,6) then 1 else 0 end) as edits,
        sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as closes,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopened
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
    group by ph.postid
),
owner_badge_summary as (
    select
        u.id as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold,
        sum(case when b.class = 2 then 1 else 0 end) as silver,
        sum(case when b.class = 3 then 1 else 0 end) as bronze,
        count(*) as total_badges
    from users u
    left join badges b on b.userid = u.id
    group by u.id
),
question_owner as (
    select
        qm.question_id,
        u.id as owner_id,
        u.displayname as owner_name,
        u.reputation,
        u.location,
        coalesce(obs.total_badges,0) as total_badges,
        coalesce(obs.gold,0) as gold_badges,
        coalesce(obs.silver,0) as silver_badges,
        coalesce(obs.bronze,0) as bronze_badges
    from question_metrics qm
    left join users u on u.id = qm.owner_user_id
    left join owner_badge_summary obs on obs.user_id = u.id
),
best_answers as (
    select
        ar.question_id,
        ar.answer_id,
        ar.owner_user_id,
        ar.score as best_answer_score,
        ar.upvotes as best_answer_up,
        ar.downvotes as best_answer_down,
        ar.is_accepted
    from answer_rank ar
    where ar.rn = 1
),
comment_sentiment as (
    select
        p.id as post_id,
        avg(case
                when lower(c.text) similar to '%(thanks|thank you|great|helpful|awesome)%' then 1
                when lower(c.text) similar to '%(stupid|bad|wrong|terrible|useless)%' then -1
                else 0
            end) as sentiment_score,
        count(*) as comment_count
    from posts p
    left join comments c on c.postid = p.id
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
    group by p.id
),
activity_windows as (
    select
        qm.question_id,
        qm.creationdate,
        sum(1) over (order by qm.creationdate rows between unbounded preceding and current row) as running_q_count,
        avg(qm.score) over (order by qm.creationdate rows between unbounded preceding and current row) as running_avg_score
    from question_metrics qm
),
recent_user_activity as (
    select
        qa.owner_id as user_id,
        count(*) as user_q_count,
        avg(qm.score) as avg_q_score,
        sum(coalesce(hn.hot_score_z,0)) as agg_hot_z
    from question_owner qa
    join question_metrics qm on qm.question_id = qa.question_id
    left join hotness_norm hn on hn.question_id = qm.question_id
    group by qa.owner_id
),
topk as (
    select
        qm.question_id,
        dense_rank() over (order by hn.hot_score_z desc NULLS LAST) as hot_rank_desc,
        dense_rank() over (order by qm.viewcount desc NULLS LAST) as views_rank_desc,
        dense_rank() over (order by qm.score desc NULLS LAST) as score_rank_desc
    from question_metrics qm
    left join hotness_norm hn on hn.question_id = qm.question_id
),
final as (
    select
        qm.question_id,
        qm.creationdate,
        qm.score,
        qm.viewcount,
        qm.answercount,
        qm.commentcount,
        qm.tag_count,
        coalesce(hn.hot_score_z, 0) as hot_score_z,
        ts.tag as top_tag_example,
        ts.avg_hot_z as tag_avg_hot_z,
        qa.owner_id,
        qa.owner_name,
        qa.reputation as owner_reputation,
        qa.location as owner_location,
        qa.total_badges,
        ba.answer_id as best_answer_id,
        ba.best_answer_score,
        ba.is_accepted,
        ea.edits,
        ea.closes,
        ea.reopened,
        cs.sentiment_score,
        aw.running_q_count,
        aw.running_avg_score,
        rua.user_q_count,
        rua.avg_q_score,
        rua.agg_hot_z,
        tk.hot_rank_desc,
        tk.views_rank_desc,
        tk.score_rank_desc,
        case
            when (coalesce(hn.hot_score_z,0) > coalesce(ts.avg_hot_z,0) + 1) then 'outlier_hot'
            when ea.closes > 0 and coalesce(hn.hot_score_z,0) < 0 then 'controversial'
            when ba.is_accepted = 1 and ba.best_answer_score >= 0 then 'resolved'
            when qm.closeddate is not null then 'closed'
            else 'active'
        end as category
    from question_metrics qm
    left join hotness_norm hn on hn.question_id = qm.question_id
    left join lateral (
        select ts.tag, ts.avg_hot_z
        from tag_explode te
        join tag_stats ts on ts.tag = te.tag
        where te.question_id = qm.question_id
        order by ts.avg_hot_z desc, ts.q_count desc
        limit 1
    ) ts on true
    left join question_owner qa on qa.question_id = qm.question_id
    left join best_answers ba on ba.question_id = qm.question_id
    left join edits_and_closures ea on ea.question_id = qm.question_id
    left join comment_sentiment cs on cs.post_id = qm.question_id
    left join activity_windows aw on aw.question_id = qm.question_id
    left join recent_user_activity rua on rua.user_id = qa.owner_id
    left join topk tk on tk.question_id = qm.question_id
)
select
    f.*
from final f
where
    (f.hot_rank_desc <= 100
     or f.views_rank_desc <= 100
     or f.score_rank_desc <= 100)
  and (f.owner_reputation is null
       or f.owner_reputation >= coalesce((select percentile_disc(0.75) within group (order by reputation) from users), 0))
  and (f.sentiment_score is null or f.sentiment_score > -0.5)
  and (f.category <> 'closed' or f.edits >= 1)
order by
    coalesce(f.hot_score_z,0) desc NULLS LAST,
    f.views_rank_desc asc NULLS LAST,
    f.score_rank_desc asc NULLS LAST
limit 250;