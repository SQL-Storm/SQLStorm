-- {"query": "3000.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1385} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        bht.Name as LastPostHistoryTypeName,
        ph.CreationDate as LastPostHistoryDate,
        cmt.CountComments,
        COALESCE(vtc.UpVotes,0) as TotalUpVotes,
        COALESCE(vtc.DownVotes,0) as TotalDownVotes,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select ph.PostId, ph.PostHistoryTypeId, max(ph.CreationDate) as CreationDate
        from PostHistory ph
        group by ph.PostId, ph.PostHistoryTypeId
    ) phmax on phmax.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = phmax.CreationDate
    left join PostHistoryTypes bht on bht.Id = ph.PostHistoryTypeId
    left join (
        select PostId, count(*) as CountComments
        from Comments
        group by PostId
    ) cmt on cmt.PostId = p.Id
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) vtc on vtc.PostId = p.Id
    where u.Reputation > 1000
),
UserTagStats as (
    select
        r.UserId,
        unnest(string_to_array(substring(r.Tags from 2 for length(r.Tags)-2), '><')) as Tag,
        count(*) as PostsPerTag
    from RecursiveUserActivity r
    where r.Tags is not null
    group by r.UserId, Tag
),
HighActivityTags as (
    select UserId, Tag, PostsPerTag
    from UserTagStats
    where PostsPerTag > 5
),
PostWithAnswerStats as (
    select q.Id as QuestionId,
           q.Title,
           q.OwnerUserId,
           q.Score as QuestionScore,
           q.ViewCount as QuestionViews,
           q.Tags,
           count(a.Id) as AnswerCount,
           avg(a.Score) as AvgAnswerScore,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as QuestionUpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as QuestionDownVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.Tags
),
TopUsersByAnswerScore as (
    select OwnerUserId, sum(Score) as TotalAnswerScore
    from Posts
    where PostTypeId = 2
    group by OwnerUserId
    having sum(Score) > 100
),
UserRankings as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ta.TotalAnswerScore, 0) as TotalAnswerScore,
        rank() over (order by coalesce(ta.TotalAnswerScore, 0) desc, u.Reputation desc) as AnswerScoreRank
    from Users u
    left join TopUsersByAnswerScore ta on ta.OwnerUserId = u.Id
),
DuplicatesLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
CandidateQuestions as (
    select pq.QuestionId, pq.Title, pq.OwnerUserId, pq.QuestionScore, pq.QuestionViews, pq.Tags,
        pq.AnswerCount, pq.AvgAnswerScore,
        (select count(*) from Comments c where c.PostId = pq.QuestionId) as CommentCount,
        (select count(*) from PostHistory ph where ph.PostId = pq.QuestionId and ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        (select count(*) from Votes v where v.PostId = pq.QuestionId and v.VoteTypeId = 6) as CloseVotes,
        du.RelatedPostId as DuplicateOfPostId
    from PostWithAnswerStats pq
    left join DuplicatesLinkedPosts du on du.PostId = pq.QuestionId
    where pq.AnswerCount > 2 and pq.QuestionScore > 5
)
select
    cuq.QuestionId,
    cuq.Title,
    u.DisplayName as QuestionOwner,
    cuq.QuestionScore,
    cuq.QuestionViews,
    cuq.AnswerCount,
    cuq.AvgAnswerScore,
    cuq.CommentCount,
    cuq.CloseReopenEvents,
    cuq.CloseVotes,
    cuq.DuplicateOfPostId,
    dupq.Title as DuplicateOfTitle,
    rank() over (order by cuq.QuestionScore desc, cuq.AnswerCount desc) as QuestionRank,
    us.AnswerScoreRank as OwnerAnswerScoreRank,
    concat(
        'User ', u.DisplayName, ' has reputation ', u.Reputation, 
        ' and ranks ', us.AnswerScoreRank, ' in answer scoring.'
    ) as UserSummary,
    case
        when cuq.CloseVotes > 0 then 'Likely to be closed'
        when cuq.DuplicateOfPostId is not null then 'Marked duplicate'
        else 'Active question'
    end as Status,
    (select string_agg(Tag, ', ') from HighActivityTags hat where hat.UserId = u.Id) as TopTagsForUser
from CandidateQuestions cuq
left join Posts dupq on dupq.Id = cuq.DuplicateOfPostId
left join Users u on u.Id = cuq.OwnerUserId
left join UserRankings us on us.Id = u.Id
where cuq.QuestionViews > 1000
order by QuestionRank
limit 100;