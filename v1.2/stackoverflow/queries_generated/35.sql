-- {"query": "35.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1734} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (order by u.Reputation desc) as ReputationRank,
        rank() over (partition by u.Location order by u.Reputation desc) as LocationReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(vc.UpVotes, 0) as UpVotes,
        coalesce(vc.DownVotes, 0) as DownVotes,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vc on vc.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct ph.Id) as TotalEdits,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) as TotalVotesCast,
        max(p.CreationDate) as LastPostDate,
        max(ph.CreationDate) as LastEditDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    uas.TotalPosts,
    uas.TotalEdits,
    uas.TotalComments,
    uas.TotalVotesCast,
    tpq.Id as TopQuestionId,
    tpq.Title as TopQuestionTitle,
    tpq.Score as TopQuestionScore,
    tpa.Id as TopAnswerId,
    tpa.Score as TopAnswerScore,
    aast.AnswerId as AcceptedAnswerId,
    aast.AnswerScore as AcceptedAnswerScore,
    pld.RelatedPostId as DuplicateOfPostId,
    pld.RelatedPostTitle as DuplicateOfPostTitle,
    rth.Level as TagHierarchyLevel,
    rth.TagName as TagInHierarchy,
    row_number() over (partition by u.Id order by tpq.Score desc nulls last) as UserTopQuestionRank
from UserReputationWindow u
left join (
    select
        UserId,
        max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts
    group by UserId
) ubc on ubc.UserId = u.Id
left join UserActivitySummary uas on uas.Id = u.Id
left join (
    select
        p.OwnerUserId,
        p.Id,
        p.Title,
        p.Score
    from Posts p
    where p.PostTypeId = 1
) tpq on tpq.OwnerUserId = u.Id
left join (
    select
        p.OwnerUserId,
        p.Id,
        p.Score
    from Posts p
    where p.PostTypeId = 2
) tpa on tpa.OwnerUserId = u.Id
left join AcceptedAnswerStats aast on aast.AnswerOwner = u.Id
left join PostLinkDuplicates pld on pld.PostId = aast.QuestionId
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(tpq.Tags, ''), '><'))
where u.Reputation > 1000
  and (u.Location is not null and u.Location <> '')
  and (tpq.Score > 10 or tpa.Score > 10)
order by u.Reputation desc, uas.TotalPosts desc
limit 100;