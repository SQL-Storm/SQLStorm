-- {"query": "725.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1368} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
FilteredPosts as (
    select * from RecursiveUserPosts
    where PostRank <= 10
),
PostScoreStats as (
    select
        fp.UserId,
        count(*) as TotalPosts,
        sum(fp.Score) as TotalScore,
        avg(fp.Score) as AvgScore,
        max(fp.Score) as MaxScore,
        min(fp.Score) as MinScore,
        sum(case when fp.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when fp.PostTypeId = 2 then 1 else 0 end) as AnswerCount
    from FilteredPosts fp
    group by fp.UserId
),
PostComments as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(u.DisplayName, c.UserDisplayName), ', ') as CommenterNames
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = c.UserId
    group by p.Id
),
PostVotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
),
TopBadges as (
    select
        UserId,
        string_agg(BadgeName || '(' || Class || ')', ', ') as RecentBadges
    from UserBadgesRanked
    where BadgeRank <= 5
    group by UserId
),
DuplicatePostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
QuestionsWithAcceptedAnswerScores as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Score as QuestionScore,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1
      and p.AcceptedAnswerId is not null
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalUserPosts,
        count(distinct c.Id) as TotalUserComments,
        coalesce(sum(vs.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vs.DownVotes), 0) as TotalDownVotes,
        coalesce(sum(vs.FavoriteVotes), 0) as TotalFavorites,
        coalesce(count(distinct b.Id), 0) as BadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vs on vs.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    uas.UserId,
    uas.DisplayName,
    ps.TotalPosts,
    ps.AvgScore,
    ps.MaxScore,
    ps.MinScore,
    ps.QuestionCount,
    ps.AnswerCount,
    coalesce(tb.RecentBadges, '(none)') as RecentBadges,
    (
        select count(*)
        from DuplicatePostLinks dpl
        where dpl.PostId in (
            select PostId from FilteredPosts where UserId = uas.UserId
        )
    ) as UserDuplicateLinksCount,
    (
        select string_agg(distinct t.TagName, ', ')
        from Tags t
        join Posts pt on pt.Id = t.ExcerptPostId or pt.Id = t.WikiPostId
        where pt.OwnerUserId = uas.UserId
        limit 3
    ) as SampleTags,
    (
        select avg(qa.AcceptedAnswerScore)
        from QuestionsWithAcceptedAnswerScores qa
        where qa.AnswerOwnerUserId = uas.UserId
          and qa.AcceptedAnswerScore is not null
    ) as AvgAcceptedAnswerScore,
    (
        select count(*)
        from Posts p2
        where p2.OwnerUserId = uas.UserId
          and p2.PostTypeId = 1
          and p2.ClosedDate is not null
    ) as ClosedQuestionsCount,
    (
        select max(ph.CreationDate)
        from PostHistory ph
        where ph.UserId = uas.UserId
          and ph.PostHistoryTypeId in (10, 11, 12, 13)
    ) as LastModerationActionDate
from UserActivitySummary uas
join PostScoreStats ps on ps.UserId = uas.UserId
left join TopBadges tb on tb.UserId = uas.UserId
where ps.TotalPosts > 5
  and ps.AvgScore > 1.5
order by ps.TotalPosts desc, ps.AvgScore desc
limit 50;