-- {"query": "366.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1517} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Name is not null
),
LatestBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where rn = 1
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score else null end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score else null end) as AvgAnswerScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        qas.QuestionCount,
        qas.AnswerCount,
        qas.AvgQuestionScore,
        qas.AvgAnswerScore,
        qas.TotalQuestionViews,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join QuestionAnswerStats qas on u.Id = qas.OwnerUserId
),
PostWithCloseReason as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
TopTags as (
    select
        t.TagName,
        t.Count,
        coalesce(p.ViewCountSum,0) as TotalViews,
        coalesce(p.PostCount,0) as PostCount
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            sum(p.ViewCount) as ViewCountSum,
            count(*) as PostCount
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
        group by TagName
    ) p on t.TagName = p.TagName
    where t.Count > 1000
    order by TotalViews desc nulls last
    limit 10
),
UserCommentStats as (
    select
        c.UserId,
        count(c.Id) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotesGiven,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotesGiven,
        count(distinct v.PostId) as DistinctPostsVoted
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
UserSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        lub.BadgeName,
        lub.Class as BadgeClass,
        qas.QuestionCount,
        qas.AnswerCount,
        ucs.CommentCount,
        ucs.AvgCommentScore,
        uvs.UpVotesGiven,
        uvs.DownVotesGiven,
        uvs.DistinctPostsVoted,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    left join LatestBadges lub on u.Id = lub.UserId
    left join QuestionAnswerStats qas on u.Id = qas.OwnerUserId
    left join UserCommentStats ucs on u.Id = ucs.UserId
    left join UserVoteStats uvs on u.Id = uvs.UserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        0 as Level,
        null::int as ParentTagId
    from Tags t
    where t.IsRequired = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        r.Level + 1,
        r.Id as ParentTagId
    from Tags t
    join RecursiveTagHierarchy r on t.IsRequired = 0 and t.Id <> r.Id and t.Count < r.Count
    where r.Level < 3
)
select
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.BadgeName,
    case us.BadgeClass
        when 1 then 'Gold'
        when 2 then 'Silver'
        when 3 then 'Bronze'
        else 'None'
    end as BadgeClass,
    us.QuestionCount,
    us.AnswerCount,
    us.CommentCount,
    us.AvgCommentScore,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.DistinctPostsVoted,
    dt.PostTitle as DuplicatePostTitle,
    dt.RelatedPostTitle as DuplicateRelatedTitle,
    tt.TagName as PopularTag,
    tt.TotalViews as PopularTagViews,
    rth.Level as TagHierarchyLevel,
    rth.ParentTagId
from UserSummary us
left join DuplicateLinks dt on dt.PostId in (
    select p.Id from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId = 1
)
left join TopTags tt on true
left join RecursiveTagHierarchy rth on rth.TagName = tt.TagName
where us.Reputation > 1000
order by us.Reputation desc, us.UserId
limit 100;