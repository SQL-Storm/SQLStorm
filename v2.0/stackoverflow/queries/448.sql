-- {"query": "448.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2940}
with recent_questions as (
    select
        p.id as question_id,
        p.creationdate,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        coalesce(p.answercount, 0) as answercount
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner_id,
        a.creationdate as answer_creationdate,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
first_answer as (
    select
        a.question_id,
        min(a.answer_creationdate) as first_answer_time
    from answers a
    group by a.question_id
),
question_votes as (
    select
        v.postid as question_id,
        sum(case when vt.name = 'UpMod' then 1 when vt.name = 'DownMod' then -1 else 0 end) as net_votes,
        sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites,
        sum(case when vt.name = 'BountyStart' then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when vt.name = 'BountyClose' then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        max(case when vt.name = 'AcceptedByOriginator' then 1 else 0 end) as has_accept_event
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
comment_activity as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        sum(greatest(c.score,0)) as nonneg_comment_score,
        min(c.creationdate) as first_comment_time,
        max(c.creationdate) as last_comment_time
    from comments c
    group by c.postid
),
dup_links as (
    select
        pl.postid as question_id,
        sum(case when lt.name = 'Duplicate' then 1 else 0 end) as dup_count_out,
        sum(case when lt.name = 'Linked' then 1 else 0 end) as linked_count_out,
        sum(case when lt.name not in ('Duplicate','Linked') then 1 else 0 end) as other_links_out
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    group by pl.postid
),
dup_incoming as (
    select
        pl.relatedpostid as question_id,
        sum(case when lt.name = 'Duplicate' then 1 else 0 end) as dup_count_in,
        sum(case when lt.name = 'Linked' then 1 else 0 end) as linked_count_in
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    group by pl.relatedpostid
),
tag_explode as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from recent_questions q
    where q.tags is not null
),
tag_popularity as (
    select
        te.question_id,
        avg(coalesce(t.count,0)) over (partition by te.question_id) as avg_tag_count,
        max(coalesce(t.count,0)) over (partition by te.question_id) as max_tag_count,
        count(*) over (partition by te.question_id) as tag_count
    from tag_explode te
    left join tags t on t.tagname = te.tag
),
edits as (
    select
        ph.postid as question_id,
        sum(case when pht.name in ('Edit Title','Edit Body','Edit Tags') then 1 else 0 end) as edit_events,
        min(case when pht.name in ('Edit Title','Edit Body','Edit Tags') then ph.creationdate end) as first_edit_time,
        sum(case when pht.name in ('Post Closed') then 1 else 0 end) as closed_events,
        min(case when pht.name in ('Post Closed') then ph.creationdate end) as first_close_time,
        sum(case when pht.name in ('Post Reopened') then 1 else 0 end) as reopen_events
    from posthistory ph
    join posthistorytypes pht on pht.id = ph.posthistorytypeid
    group by ph.postid
),
owner_stats as (
    select
        u.id as user_id,
        u.reputation,
        u.creationdate as user_creation,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        coalesce(nullif(trim(u.location),''),'(unknown)') as norm_location
    from users u
),
owner_badges as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
accepted_answer as (
    select
        q.id as question_id,
        q.acceptedanswerid as accepted_answer_id
    from posts q
    where q.posttypeid = 1 and q.acceptedanswerid is not null
),
accepted_answerer as (
    select
        aa.question_id,
        a.owneruserid as accepted_answer_user_id
    from accepted_answer aa
    join posts a on a.id = aa.accepted_answer_id
),
answerer_mix as (
    select
        a.question_id,
        count(distinct a.answer_owner_id) as distinct_answerers,
        sum(case when a.answer_score > 0 then 1 else 0 end) as pos_answers,
        sum(case when a.answer_score < 0 then 1 else 0 end) as neg_answers,
        max(a.answer_score) as max_answer_score,
        min(a.answer_score) as min_answer_score
    from answers a
    group by a.question_id
),
question_quality as (
    select
        q.question_id,
        q.creationdate,
        q.owneruserid,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        fv.first_answer_time,
        qa.net_votes,
        qa.favorites,
        qa.bounty_started,
        qa.bounty_awarded,
        qa.has_accept_event,
        ca.comment_count,
        ca.nonneg_comment_score,
        ca.first_comment_time,
        ca.last_comment_time,
        coalesce(dlo.dup_count_out,0) as dup_count_out,
        coalesce(dlo.linked_count_out,0) as linked_count_out,
        coalesce(dlo.other_links_out,0) as other_links_out,
        coalesce(dli.dup_count_in,0) as dup_count_in,
        coalesce(dli.linked_count_in,0) as linked_count_in,
        tp.avg_tag_count,
        tp.max_tag_count,
        tp.tag_count,
        ed.edit_events,
        ed.first_edit_time,
        ed.closed_events,
        ed.first_close_time,
        ed.reopen_events,
        am.distinct_answerers,
        am.pos_answers,
        am.neg_answers,
        am.max_answer_score,
        am.min_answer_score
    from recent_questions q
    left join first_answer fv on fv.question_id = q.question_id
    left join question_votes qa on qa.question_id = q.question_id
    left join comment_activity ca on ca.post_id = q.question_id
    left join dup_links dlo on dlo.question_id = q.question_id
    left join dup_incoming dli on dli.question_id = q.question_id
    left join tag_popularity tp on tp.question_id = q.question_id
    left join edits ed on ed.question_id = q.question_id
    left join answerer_mix am on am.question_id = q.question_id
),
ranked as (
    select
        qq.*,
        extract(epoch from (coalesce(qq.first_answer_time, cast('2024-10-01 12:34:56' as timestamp)) - qq.creationdate)) as secs_to_first_answer,
        extract(epoch from (coalesce(qq.first_edit_time, cast('2024-10-01 12:34:56' as timestamp)) - qq.creationdate)) as secs_to_first_edit,
        extract(epoch from (coalesce(qq.first_close_time, cast('2024-10-01 12:34:56' as timestamp)) - qq.creationdate)) as secs_to_close,
        case
            when qq.score is null then 0
            when qq.viewcount is null or qq.viewcount = 0 then qq.score
            else cast(qq.score as numeric) / nullif(qq.viewcount,0)
        end as score_per_view,
        coalesce(qq.net_votes,0) + coalesce(qq.favorites,0) * 2 as engagement_index,
        (coalesce(qq.pos_answers,0) - coalesce(qq.neg_answers,0)) as answer_sentiment,
        (coalesce(qq.bounty_awarded,0) - coalesce(qq.bounty_started,0)) as bounty_delta,
        row_number() over (order by coalesce(qq.net_votes,0) desc, coalesce(qq.viewcount,0) desc) as rn_popularity,
        dense_rank() over (order by coalesce(qq.closed_events,0) desc, coalesce(qq.dup_count_in,0) desc) as drn_controversy,
        percent_rank() over (order by coalesce(qq.viewcount,0)) as pr_views
    from question_quality qq
),
owner_enriched as (
    select
        r.*,
        os.reputation,
        os.upvotes as owner_upvotes,
        os.downvotes as owner_downvotes,
        os.profile_views,
        os.norm_location,
        ob.gold_badges,
        ob.silver_badges,
        ob.bronze_badges,
        ob.tag_badges,
        ob.last_badge_date,
        aa.accepted_answer_user_id,
        case when aa.accepted_answer_user_id = r.owneruserid then 1 else 0 end as self_accepted
    from ranked r
    left join owner_stats os on os.user_id = r.owneruserid
    left join owner_badges ob on ob.userid = r.owneruserid
    left join accepted_answerer aa on aa.question_id = r.question_id
),
location_rollup as (
    select
        norm_location,
        count(*) as loc_questions,
        avg(coalesce(score,0)) as loc_avg_score,
        avg(coalesce(viewcount,0)) as loc_avg_views
    from owner_enriched
    group by norm_location
),
final as (
    select
        oe.*,
        lr.loc_questions,
        lr.loc_avg_score,
        lr.loc_avg_views,
        case
            when oe.tag_count is null or oe.tag_count = 0 then 'untagged'
            when oe.tag_count = 1 then 'mono-tag'
            when oe.tag_count between 2 and 3 then 'few-tags'
            else 'many-tags'
        end as tag_bucket,
        case
            when coalesce(oe.closed_events,0) > 0 then 'closed'
            when coalesce(oe.dup_count_in,0) > 0 then 'duplicate'
            else 'open'
        end as status_bucket,
        case
            when oe.secs_to_first_answer is null then null
            when oe.secs_to_first_answer <= 3600 then 'within_1h'
            when oe.secs_to_first_answer <= 86400 then 'within_1d'
            when oe.secs_to_first_answer <= 604800 then 'within_1w'
            else 'later'
        end as time_to_first_answer_bucket
    from owner_enriched oe
    left join location_rollup lr on lr.norm_location = oe.norm_location
)
select
    f.question_id,
    coalesce(nullif(trim(f.title),''),'(no title)') as title,
    f.creationdate,
    f.owneruserid,
    f.reputation,
    f.gold_badges || '/' || f.silver_badges || '/' || f.bronze_badges as badge_mix,
    f.score,
    f.viewcount,
    f.answercount,
    f.net_votes,
    f.favorites,
    f.engagement_index,
    f.score_per_view,
    f.distinct_answerers,
    f.max_answer_score,
    f.min_answer_score,
    f.dup_count_in,
    f.dup_count_out,
    f.closed_events,
    f.status_bucket,
    f.tag_bucket,
    f.pr_views,
    f.rn_popularity,
    f.drn_controversy,
    f.time_to_first_answer_bucket,
    f.secs_to_first_answer,
    f.secs_to_first_edit,
    f.secs_to_close,
    f.norm_location,
    f.loc_questions,
    f.loc_avg_score,
    f.loc_avg_views,
    coalesce(f.self_accepted,0) as self_accepted,
    case when f.engagement_index > 50 and coalesce(f.closed_events,0) = 0 then 'candidate' else 'normal' end as spotlight_flag
from final f
where
    (
        f.status_bucket = 'open'
        or (f.status_bucket = 'duplicate' and coalesce(f.engagement_index,0) >= 10)
    )
    and coalesce(f.avg_tag_count,0) >= 0
    and (
        f.owneruserid is null
        or exists (
            select 1
            from badges b2
            where b2.userid = f.owneruserid
              and b2.class in (1,2)
        )
    )
order by
    f.engagement_index desc,
    f.viewcount desc,
    f.score desc
limit 500;