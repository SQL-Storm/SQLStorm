-- {"query": "5035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1053} 
with t_user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(p.Score) filter (where p.PostTypeId in (1,2)), 0) as TotalPostScore,
        coalesce(sum(b.Class = 1::smallint::int),0) as GoldBadges,
        coalesce(sum(b.Class = 2::smallint::int),0) as SilverBadges,
        coalesce(sum(b.Class = 3::smallint::int),0) as BronzeBadges
    from Users u
        left join Posts p on u.Id = p.OwnerUserId
        left join Comments c on c.UserId = u.Id
        left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
t_recent_questions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > now() - interval '90 days'
),
t_linked_dupes as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkType,
        case when pl.LinkTypeId = 3 then 1 else 0 end as IsDuplicate
    from PostLinks pl
      inner join LinkTypes lt on pl.LinkTypeId = lt.Id
),
t_close_votes as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastClosedDate,
        count(*) as CloseEventCount,
        cr.Name as CloseReason
    from PostHistory ph
      left join CloseReasonTypes cr on
        cr.Id = ph.Comment::int
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, cr.Name
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalPostScore,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    rq.QuestionId,
    rq.Title,
    rq.Tags,
    rq.CreationDate as QuestionCreationDate,
    rq.Score as QuestionScore,
    rq.ViewCount as QuestionViews,
    rq.AnswerCount as QuestionAnswers,
    string_agg(distinct ld.LinkType || ':' || ld.RelatedPostId, ', ') as LinkedPosts,
    sum(ld.IsDuplicate)::int as DuplicateCount,
    coalesce(cv.CloseReason, 'Never Closed') as LastCloseReason,
    cv.LastClosedDate as LastClosedDate,
    cv.CloseEventCount as CloseCount,
    case
        when rq.AnswerCount = 0 then 'Unanswered'
        when rq.Score < 0 then 'Low Quality'
        when rq.ViewCount > 5000 then 'Popular'
        when rq.AnswerCount > 5 then 'Hot'
        else 'Normal'
    end as QuestionFlag,
    array_to_string(string_to_array(coalesce(rq.Tags,''),'><'), ', ') as TagList,
    (
        select count(*)
        from Comments c
        where c.PostId = rq.QuestionId and c.Score >= 5
    ) as HighScoreComments,
    (
        select count(*)
        from Votes v
        where v.PostId = rq.QuestionId and v.VoteTypeId = 2
    ) as UpvoteCount
from t_user_activity ua
    left join t_recent_questions rq on rq.OwnerUserId = ua.UserId and rq.rn <= 2
    left join t_linked_dupes ld on ld.PostId = rq.QuestionId
    left join t_close_votes cv on cv.PostId = rq.QuestionId
where ua.Reputation >= 1000
group by
    ua.UserId, ua.DisplayName, ua.Reputation, ua.Location,
    ua.QuestionCount, ua.AnswerCount, ua.CommentCount, ua.TotalPostScore,
    ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
    rq.QuestionId, rq.Title, rq.Tags, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount,
    cv.CloseReason, cv.LastClosedDate, cv.CloseEventCount
order by
    ua.TotalPostScore desc,
    rq.Score desc nulls last
limit 100;