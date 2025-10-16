-- {"query": "550.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1652} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from Badges b
    where b.Date > current_date - interval '2 years'
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        string_agg(distinct ub.Name, ', ' order by ub.Class) as RecentBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > current_date - interval '1 year'
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    left join UserBadgesRanked ub on ub.UserId = u.Id and ub.rn <= 3
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostActivityStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        max(ph.CreationDate) as LastEditDate,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId, p.ClosedDate
),
AcceptedAnswerStats as (
    select
        p.Id as QuestionId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u on u.Id = p1.OwnerUserId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3
),
ComplexUserActivity as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1 and p.CreationDate > current_date - interval '6 months') as RecentQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2 and p.CreationDate > current_date - interval '6 months') as RecentAnswers,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        max(ph.CreationDate) as LastPostEdit,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
    group by u.Id, u.DisplayName
    having count(distinct p.Id) > 10
)
select
    tu.DisplayName as UserName,
    tu.Reputation,
    tu.Location,
    tu.QuestionsCount,
    tu.AnswersCount,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    tu.RecentBadges,
    pas.Score as TopQuestionScore,
    pas.ViewCount as TopQuestionViews,
    pas.CommentCount as TopQuestionComments,
    aas.AcceptedAnswerScore,
    aas.AnswerOwnerName,
    aas.AnswerOwnerReputation,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as DuplicateRelatedPostOwner,
    cua.RecentQuestions as UserRecentQuestions,
    cua.RecentAnswers as UserRecentAnswers,
    cua.TotalUpVotes as UserTotalUpVotes,
    cua.TotalDownVotes as UserTotalDownVotes,
    cua.LastPostEdit,
    cua.HasClosedPosts
from TopUsers tu
left join lateral (
    select p.Score, p.ViewCount, p.CommentCount
    from PostActivityStats p
    where p.OwnerUserId = tu.Id and p.PostTypeId = 1
    order by p.Score desc
    limit 1
) pas on true
left join AcceptedAnswerStats aas on aas.QuestionId = pas.Id
left join lateral (
    select dl.PostTitle, dl.RelatedPostTitle, dl.PostOwner, dl.RelatedPostOwner
    from DuplicateLinks dl
    join Posts p on p.Id = dl.PostId
    where p.OwnerUserId = tu.Id
    order by dl.PostId desc
    limit 1
) dl on true
left join ComplexUserActivity cua on cua.Id = tu.Id
where tu.QuestionsCount > 5
order by tu.Reputation desc, pas.Score desc
limit 100;