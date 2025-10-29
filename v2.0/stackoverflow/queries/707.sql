-- {"query": "707.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3118}
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.owneruserid as owneruserid,
        p.title,
        p.tags,
        coalesce(p.answercount, 0) as answercount,
        coalesce(p.commentcount, 0) as commentcount,
        p.acceptedanswerid,
        p.parentid
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
users_activity as (
    select
        u.id as userid,
        u.reputation,
        u.creationdate,
        u.displayname,
        u.location,
        coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as netvotes,
        coalesce(u.views, 0) as profileviews,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges,
        count(distinct p.id) as total_posts
    from users u
    left join badges b on b.userid = u.id
    left join posts p on p.owneruserid = u.id
    group by u.id, u.reputation, u.creationdate, u.displayname, u.location, u.upvotes, u.downvotes, u.views
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 1) as accepted_marks,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        sum(coalesce(v.bountyamount,0)) as bounty_amount
    from votes v
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_date,
        sum(case when c.score >= 5 then 1 else 0 end) as high_score_comments
    from comments c
    group by c.postid
),
links_agg as (
    select
        l.postid,
        count(*) filter (where l.linktypeid = 1) as linked_count,
        count(*) filter (where l.linktypeid = 3) as duplicate_links
    from postlinks l
    group by l.postid
),
close_events as (
    select
        ph.postid,
        min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_close_date,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes,
        count(*) filter (where ph.posthistorytypeid in (33,34)) as post_notices
    from posthistory ph
    group by ph.postid
),
question_core as (
    select
        q.id as question_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.commentcount,
        q.acceptedanswerid,
        q.owneruserid,
        va.upvotes,
        va.downvotes,
        va.accepted_marks,
        va.bounty_events,
        va.bounty_amount,
        ca.comment_count as q_comment_count,
        ca.last_comment_date as q_last_comment_date,
        la.linked_count,
        la.duplicate_links,
        ce.first_close_date,
        ce.last_reopen_date,
        ce.close_votes,
        ce.reopen_votes,
        ce.post_notices
    from recent_posts q
    left join votes_agg va on va.postid = q.id
    left join comments_agg ca on ca.postid = q.id
    left join links_agg la on la.postid = q.id
    left join close_events ce on ce.postid = q.id
    where q.posttypeid = 1
),
answer_core as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.creationdate,
        a.score,
        a.owneruserid,
        va.upvotes,
        va.downvotes,
        va.accepted_marks,
        va.bounty_events,
        va.bounty_amount,
        row_number() over (partition by a.parentid order by coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc, a.score desc, a.creationdate asc) as rn_by_score,
        dense_rank() over (partition by a.parentid order by a.creationdate asc) as age_rank
    from recent_posts a
    left join votes_agg va on va.postid = a.id
    where a.posttypeid = 2
),
accepted_vs_top as (
    select
        ac.question_id,
        ac.answer_id as accepted_answer_id,
        ac.owneruserid as accepted_ownerid,
        ac.score as accepted_score,
        coalesce(ac.upvotes,0) - coalesce(ac.downvotes,0) as accepted_net_votes,
        tt.answer_id as top_answer_id,
        tt.owneruserid as top_ownerid,
        tt.score as top_score,
        coalesce(tt.upvotes,0) - coalesce(tt.downvotes,0) as top_net_votes,
        case when tt.answer_id is not null and ac.answer_id is not null and tt.answer_id = ac.answer_id then 1 else 0 end as accepted_is_top
    from answer_core ac
    join question_core q on q.question_id = ac.question_id and q.acceptedanswerid = ac.answer_id
    left join lateral (
        select a2.answer_id, a2.question_id, a2.creationdate, a2.score, a2.owneruserid, a2.upvotes, a2.downvotes
        from answer_core a2
        where a2.question_id = ac.question_id
        order by coalesce(a2.upvotes,0) - coalesce(a2.downvotes,0) desc, a2.score desc, a2.creationdate asc
        limit 1
    ) tt on true
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_core q
    where q.tags is not null and length(q.tags) > 2
),
tag_stats as (
    select
        te.question_id,
        te.tagname,
        t.count as global_tag_count,
        t.ismoderatoronly,
        t.isrequired
    from tag_expansion te
    left join tags t on lower(t.tagname) = lower(te.tagname)
),
question_quality as (
    select
        q.question_id,
        q.creationdate,
        q.title,
        q.viewcount,
        q.score,
        q.answercount,
        q.q_comment_count,
        q.linked_count,
        q.duplicate_links,
        q.close_votes,
        q.reopen_votes,
        q.first_close_date,
        q.last_reopen_date,
        avg(case when ts.global_tag_count > 0 then ln(cast(ts.global_tag_count as numeric)) else null end) as avg_log_tag_popularity,
        max(case when ts.ismoderatoronly = true then 1 else 0 end) as has_mod_only_tag,
        max(case when ts.isrequired = true then 1 else 0 end) as has_required_tag,
        count(distinct ts.tagname) as distinct_tag_count
    from question_core q
    left join tag_stats ts on ts.question_id = q.question_id
    group by q.question_id, q.creationdate, q.title, q.viewcount, q.score, q.answercount, q.q_comment_count, q.linked_count, q.duplicate_links, q.close_votes, q.reopen_votes, q.first_close_date, q.last_reopen_date
),
owner_metrics as (
    select
        q.question_id,
        ua.userid,
        ua.displayname,
        ua.location,
        ua.reputation,
        ua.netvotes,
        ua.profileviews,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.total_posts
    from question_core q
    left join users_activity ua on ua.userid = q.owneruserid
),
answer_density as (
    select
        a.question_id,
        count(*) as answers_total,
        sum(case when a.rn_by_score = 1 then 1 else 0 end) as top_answers,
        sum(case when a.age_rank = 1 then 1 else 0 end) as first_answers,
        max(a.creationdate) as last_answer_date
    from answer_core a
    group by a.question_id
),
engagement_windows as (
    select
        q.question_id,
        q.creationdate,
        sum(case when c.creationdate <= q.creationdate + interval '1 day' then 1 else 0 end) as comments_1d,
        sum(case when c.creationdate <= q.creationdate + interval '7 days' then 1 else 0 end) as comments_7d
    from question_core q
    left join comments c on c.postid = q.question_id
    group by q.question_id, q.creationdate
),
ranked_questions as (
    select
        qq.*,
        om.displayname,
        om.location,
        om.reputation,
        om.netvotes as owner_netvotes,
        om.gold_badges,
        om.silver_badges,
        om.bronze_badges,
        om.total_posts as owner_total_posts,
        coalesce(ad.answers_total, 0) as answers_total,
        coalesce(ad.top_answers, 0) as top_answers,
        coalesce(ad.first_answers, 0) as first_answers,
        ad.last_answer_date,
        ew.comments_1d,
        ew.comments_7d,
        row_number() over (order by
            coalesce(qq.score,0) desc,
            coalesce(qq.viewcount,0) desc,
            coalesce(qq.answercount,0) desc,
            qq.creationdate desc
        ) as popularity_rank,
        percent_rank() over (order by coalesce(qq.viewcount,0)) as view_pr,
        ntile(10) over (order by coalesce(qq.score,0)) as score_decile
    from question_quality qq
    left join owner_metrics om on om.question_id = qq.question_id
    left join answer_density ad on ad.question_id = qq.question_id
    left join engagement_windows ew on ew.question_id = qq.question_id
),
dup_network as (
    select
        q.question_id,
        array_agg(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicates_of,
        count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_of_count,
        count(distinct pl2.postid) filter (where pl2.linktypeid = 3) as has_duplicates_count
    from ranked_questions q
    left join postlinks pl on pl.postid = q.question_id
    left join postlinks pl2 on pl2.relatedpostid = q.question_id
    group by q.question_id
),
accepted_summary as (
    select
        q.question_id,
        case when q.answercount > 0 then
            (select max(case when avt.accepted_is_top = 1 then 1 else 0 end)
             from accepted_vs_top avt
             where avt.question_id = q.question_id)
        else null end as accepted_matches_top
    from ranked_questions q
)
select
    rq.question_id,
    rq.title,
    rq.creationdate,
    rq.score,
    rq.viewcount,
    rq.answercount,
    rq.q_comment_count as commentcount,
    rq.linked_count,
    rq.duplicate_links,
    rq.close_votes,
    rq.reopen_votes,
    rq.first_close_date,
    rq.last_reopen_date,
    rq.avg_log_tag_popularity,
    rq.has_mod_only_tag,
    rq.has_required_tag,
    rq.distinct_tag_count,
    rq.displayname as owner_displayname,
    rq.location as owner_location,
    rq.reputation as owner_reputation,
    rq.owner_netvotes,
    rq.gold_badges,
    rq.silver_badges,
    rq.bronze_badges,
    rq.owner_total_posts,
    rq.answers_total,
    rq.top_answers,
    rq.first_answers,
    rq.last_answer_date,
    rq.comments_1d,
    rq.comments_7d,
    rq.popularity_rank,
    rq.view_pr,
    rq.score_decile,
    dn.duplicates_of,
    dn.duplicate_of_count,
    dn.has_duplicates_count,
    asu.accepted_matches_top,
    case
        when rq.has_mod_only_tag = 1 then 'moderator_only'
        when rq.has_required_tag = 1 then 'required'
        when coalesce(rq.avg_log_tag_popularity, 0) < 1 then 'niche'
        else 'general'
    end as tag_profile_bucket,
    case
        when rq.close_votes > rq.reopen_votes then 'more_closes'
        when rq.reopen_votes > rq.close_votes then 'more_reopens'
        when coalesce(rq.close_votes,0) + coalesce(rq.reopen_votes,0) = 0 then 'no_activity'
        else 'balanced'
    end as close_reopen_balance,
    round((
          coalesce(rq.score,0) + coalesce(rq.viewcount,0)/100.0 + coalesce(rq.answercount,0)*2 + coalesce(rq.q_comment_count,0)*0.5
          ) * (1 + coalesce(rq.avg_log_tag_popularity,0)/10.0)
          , 2) as synthetic_popularity_score
from ranked_questions rq
left join dup_network dn on dn.question_id = rq.question_id
left join accepted_summary asu on asu.question_id = rq.question_id
where
    (rq.viewcount > 0 or rq.score > 0 or rq.answercount > 0)
    and (rq.first_close_date is null or rq.last_reopen_date is null or rq.last_reopen_date >= rq.first_close_date)
    and (asu.accepted_matches_top is null or asu.accepted_matches_top in (0,1))
order by
    synthetic_popularity_score desc,
    rq.popularity_rank asc
limit 500;