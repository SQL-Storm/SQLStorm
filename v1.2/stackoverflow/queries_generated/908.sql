-- {"query": "908.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1608} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        c.Id,
        c.TagName,
        r.Level + 1,
        r.Path || c.TagName
    from Tags c
    join RecursiveTagHierarchy r on c.Id = (
        select pst.RelatedPostId from PostLinks pst
        join Posts p1 on p1.Id = pst.PostId and p1.PostTypeId = 1
        join Posts p2 on p2.Id = pst.RelatedPostId and p2.PostTypeId = 1
        where p1.Tags like '%' || r.TagName || '%'
        and pst.LinkTypeId = 1 -- Linked
        limit 1
    ) and not c.TagName = any(r.Path)
    where r.Level < 3
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vote_counts.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vote_counts.DownVotes),0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) vote_counts on vote_counts.PostId = p.Id
    group by u.Id, u.DisplayName
),
PostWithRank as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPosts as (
    select * from PostWithRank
    where ScoreRank <= 10 or RecentRank <= 10
),
BadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select 
        bc.UserId,
        max(case when bc.Class = 1 then bc.BadgeCount else 0 end) as GoldBadges,
        max(case when bc.Class = 2 then bc.BadgeCount else 0 end) as SilverBadges,
        max(case when bc.Class = 3 then bc.BadgeCount else 0 end) as BronzeBadges
    from BadgeCounts bc
    group by bc.UserId
),
ComplexAggregates as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        u.DisplayName as OwnerName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        coalesce(phc.ClosedCount,0) as NumberOfClosures,
        coalesce(phc.ReopenCount,0) as NumberOfReopens,
        ph_last.LastEditDate,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserActivity ua on ua.UserId = p.OwnerUserId
    left join UserBadgeSummary ub on ub.UserId = p.OwnerUserId
    left join (
        select 
            PostId,
            sum(case when PostHistoryTypeId = 10 then 1 else 0 end) as ClosedCount,
            sum(case when PostHistoryTypeId = 11 then 1 else 0 end) as ReopenCount
        from PostHistory
        group by PostId
    ) phc on phc.PostId = p.Id
    left join (
        select 
            PostId,
            max(LastEditDate) as LastEditDate
        from Posts
        group by PostId
    ) ph_last on ph_last.PostId = p.Id
    where p.PostTypeId in (1,2)
),
FilteredPostsWithComments as (
    select 
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.Score) filter (where c.Score is not null) as MaxCommentScore,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighlyRatedComments
    from Comments c
    group by c.PostId
),
FinalData as (
    select 
        cp.PostId,
        cp.Title,
        cp.Tags,
        cp.OwnerName,
        cp.QuestionsAsked,
        cp.AnswersGiven,
        cp.TotalUpVotes,
        cp.TotalDownVotes,
        cp.GoldBadges,
        cp.SilverBadges,
        cp.BronzeBadges,
        cp.NumberOfClosures,
        cp.NumberOfReopens,
        cp.LastEditDate,
        fpc.CommentCount,
        fpc.MaxCommentScore,
        fpc.HighlyRatedComments,
        case 
            when cp.ScoreRank <= 3 then 'Top 3'
            when cp.ScoreRank <= 10 then 'Top 10'
            else 'Other'
        end as PerformanceBracket,
        coalesce(array_to_string(string_to_array(cp.Tags, '><'), ','), 'NoTags') as TagList,
        length(cp.Title) as TitleLength,
        (coalesce(cp.TotalUpVotes,0) - coalesce(cp.TotalDownVotes,0)) as NetVotes,
        (cp.QuestionsAsked + cp.AnswersGiven) as TotalContributions,
        (cp.GoldBadges*3 + cp.SilverBadges*2 + cp.BronzeBadges) as BadgeScore
    from ComplexAggregates cp
    left join FilteredPostsWithComments fpc on fpc.PostId = cp.PostId
)
select 
    fd.PerformanceBracket,
    fd.TagList,
    count(distinct fd.PostId) as CountOfPosts,
    avg(fd.TitleLength)::numeric(10,2) as AvgTitleLength,
    avg(fd.NetVotes)::numeric(10,2) as AvgNetVotes,
    avg(fd.TotalContributions)::numeric(10,2) as AvgUserContributions,
    avg(fd.BadgeScore)::numeric(10,2) as AvgBadgeScore,
    sum(fd.CommentCount) as TotalComments,
    sum(fd.HighlyRatedComments) as TotalHighlyRatedComments,
    string_agg(distinct fd.OwnerName, ', ') filter (where fd.OwnerName is not null) as SampleOwners
from FinalData fd
where fd.Title is not null
group by fd.PerformanceBracket, fd.TagList
order by fd.PerformanceBracket, CountOfPosts desc;