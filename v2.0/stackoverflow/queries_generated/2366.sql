-- {"query": "2366.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1430} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.Title,
        u.Reputation,
        u.Location,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
        count(*) over (partition by p.PostTypeId) as total_posts_of_type
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
      and p.CreationDate >= now() - interval '2 years'
      and (p.Tags is not null or p.PostTypeId = 2)
),
TopQuestions as (
    select *
    from RankedPosts
    where PostTypeId = 1 and rn <= 100
),
TopAnswers as (
    select *
    from RankedPosts
    where PostTypeId = 2 and rn <= 200
),
AnswerAggregates as (
    select
        a.ParentId as QuestionId,
        count(*) filter (where a.Score > 0) as PositiveAnswerCount,
        count(*) filter (where a.Score <= 0) as NonPositiveAnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        count(*) over (partition by b.UserId) as TotalBadges,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from Badges b
),
FilteredBadges as (
    select UserId, Name, Class
    from QuestionBadges
    where rn <= 5
),
ClosedQuestions as (
    select ph.PostId, ph.Comment as CloseReasonId, crt.Name as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 and ph.PostId in (select Id from TopQuestions)
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.Score is null then 0 else c.Score end) as TotalCommentScore,
        string_agg(coalesce(c.UserDisplayName, 'anonymous'), ', ') as Commenters
    from Comments c
    where c.PostId in (select Id from TopQuestions)
    group by c.PostId
),
TaggedQuestions as (
    select
        t.Id,
        t.TagName,
        t.Count as TagUsageCount,
        p.Id as PostId,
        p.Tags
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags is not null and position('<' || t.TagName || '>' in p.Tags) > 0
    where t.Count > 1000
),
CorrelatedVotes as (
    select
        p.Id as PostId,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 5) as FavoriteVotes
    from Posts p
    where p.PostTypeId = 1 and p.Id in (select Id from TopQuestions)
),
PostsWithLinks as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedPostCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicatePostCount
    from PostLinks pl
    group by pl.PostId
)
select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    u.Location as OwnerLocation,
    coalesce(a.PositiveAnswerCount, 0) as PositiveAnswerCount,
    coalesce(a.NonPositiveAnswerCount, 0) as NonPositiveAnswerCount,
    coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(cq.CommentCount, 0) as QuestionCommentCount,
    coalesce(cq.TotalCommentScore, 0) as QuestionCommentScore,
    coalesce(cv.UpVotes, 0) as QuestionUpVotes,
    coalesce(cv.DownVotes, 0) as QuestionDownVotes,
    coalesce(cv.FavoriteVotes, 0) as QuestionFavoriteVotes,
    coalesce(pl.LinkedPostCount, 0) as LinkedPosts,
    coalesce(pl.DuplicatePostCount, 0) as DuplicatePosts,
    cb.CloseReasonName,
    (select string_agg(distinct fb.Name || ' (' || 
        case fb.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ')
     from FilteredBadges fb where fb.UserId = q.OwnerUserId) as TopBadges,
    substring(q.Tags from 2 for char_length(q.Tags) - 2) as RawTags,
    array_to_string(array(
        select trim(both '><' from unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')))
    ), ', ') as TagList,
    case 
      when q.ViewCount > 10000 then 'Highly Viewed'
      when q.ViewCount between 1000 and 10000 then 'Moderately Viewed'
      else 'Low View'
    end as ViewCategory,
    row_number() over (order by q.Score desc) as GlobalRank,
    dense_rank() over (partition by u.Location order by q.Score desc) as LocationRank
from TopQuestions q
left join Users u on q.OwnerUserId = u.Id
left join AnswerAggregates a on q.Id = a.QuestionId
left join QuestionComments cq on q.Id = cq.PostId
left join CorrelatedVotes cv on q.Id = cv.PostId
left join PostsWithLinks pl on q.Id = pl.PostId
left join ClosedQuestions cb on q.Id = cb.PostId
where q.Score > 5
order by q.Score desc, cv.UpVotes desc
limit 100;