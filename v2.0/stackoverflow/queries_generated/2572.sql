-- {"query": "2572.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2070} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
      and p.Score is not null
),
PostCommentStats as (
    select
        p.Id as PostId,
        coalesce(count(c.Id),0) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
    from Posts p
    left join Comments c on p.Id = c.PostId
    group by p.Id
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicates
    group by pl.PostId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesMade,
        first_value(p.CreationDate) over (partition by u.Id order by p.CreationDate) as FirstPostDate,
        last_value(p.CreationDate) over (partition by u.Id order by p.CreationDate
            rows between unbounded preceding and unbounded following) as LastPostDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Votes v on u.Id = v.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopActiveUsers as (
    select 
        ua.Id as UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesMade,
        ua.DownVotesMade,
        ua.FirstPostDate,
        ua.LastPostDate,
        coalesce(sum(ubc.BadgeCount),0) as TotalBadges,
        max(ubc.Class) as HighestBadgeClass
    from UserActivityWindow ua
    left join UserBadgeCounts ubc on ua.Id = ubc.UserId
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade, ua.UpVotesMade, ua.DownVotesMade, ua.FirstPostDate, ua.LastPostDate
),
PostsWithDupesComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        coalesce(d.DuplicateCount, 0) as DuplicateCount,
        coalesce(pc.CommentCount, 0) as CommentCount,
        coalesce(pc.PositiveComments,0) as PositiveComments,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        case
            when p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        concat(
            substring(p.Title from 1 for 20),
            ' ... ',
            coalesce(p.Tags, 'NoTags'),
            ' [Score:',
            cast(p.Score as varchar),
            ', Views:',
            cast(p.ViewCount as varchar),
            ', Comments:',
            cast(coalesce(pc.CommentCount, 0) as varchar),
            ', Dups:',
            cast(coalesce(d.DuplicateCount, 0) as varchar),
            ']'
        ) as Snippet
    from Posts p
    left join DuplicateLinkCounts d on p.Id = d.PostId
    left join PostCommentStats pc on p.Id = pc.PostId
    where p.PostTypeId in (1,2)
),
RecursiveTagExplode as (
    select
        p.Id as PostId,
        trim(tags_table.tag) as TagName
    from PostsWithDupesComments p,
    lateral unnest(string_to_array(
        replace(replace(coalesce(p.Tags, ''), '<', ''), '>', ','), ','
    )) as tags_table(tag)
    where p.Tags is not null and p.Tags <> ''
), 
TagPopularity as (
    select
        TagName,
        count(distinct PostId) as PostCount,
        row_number() over (order by count(distinct PostId) desc) as PopularityRank
    from RecursiveTagExplode
    group by TagName
    having count(distinct PostId) > 10
),
PostsWithPopTags as (
    select 
        p.*,
        tp.PopularityRank,
        tp.PostCount as TagPostCount
    from PostsWithDupesComments p
    left join RecursiveTagExplode rte on p.Id = rte.PostId
    left join TagPopularity tp on rte.TagName = tp.TagName
    where tp.PopularityRank is not null
),
FinalUserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as NumQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as NumAnswers,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        count(distinct case when p.AcceptedAnswerId is not null then p.Id end) as QuestionsWithAcceptedAnswers,
        max(pb.HighestBadgeClass) as HighestBadgeClass,
        sum(pb.TotalBadges) as TotalBadges
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join TopActiveUsers pb on u.Id = pb.UserId
    group by u.Id, u.DisplayName
),
HighlyActiveEngagedPosts as (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.DuplicateCount,
        p.PositiveComments,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByEngagement
    from PostsWithDupesComments p
    left join Users u on p.OwnerUserId = u.Id
    where (p.Score > 50 or p.ViewCount > 1000) and p.CommentCount > 5
)
select
    fn.UserId,
    fn.DisplayName,
    fn.NumQuestions,
    fn.NumAnswers,
    coalesce(fn.AvgQuestionScore,0) as AvgQuestionScore,
    coalesce(fn.AvgAnswerScore,0) as AvgAnswerScore,
    fn.MaxQuestionViews,
    fn.MaxAnswerScore,
    fn.QuestionsWithAcceptedAnswers,
    fn.HighestBadgeClass,
    fn.TotalBadges,
    hap.Id as TopPostId,
    hap.Title as TopPostTitle,
    hap.Score as TopPostScore,
    hap.ViewCount as TopPostViews,
    hap.CommentCount as TopPostComments,
    hap.DuplicateCount as TopPostDuplicateCount,
    hap.PositiveComments as TopPostPositiveComments,
    hap.CreationDate as TopPostCreationDate,
    hap.OwnerUserId as TopPostOwnerId,
    hap.OwnerName as TopPostOwnerName,
    -- complex string expression demonstrating NULL logic and calculations
    concat(
        'User [', fn.DisplayName, '] with ', 
        cast(fn.TotalBadges as varchar), ' badges (highest class: ',
        coalesce( case fn.HighestBadgeClass 
            when 1 then 'Gold' 
            when 2 then 'Silver' 
            when 3 then 'Bronze' 
            else 'None' end, 'None'),
        ') posted top answer [', hap.Title, 
        '] scored ', cast(hap.Score as varchar),
        ' with ', cast(hap.ViewCount as varchar), ' views, ',
        cast(hap.CommentCount as varchar), ' comments; ',
        'Duplicates linked: ', cast(hap.DuplicateCount as varchar),
        '; Positive comments: ', cast(hap.PositiveComments as varchar)
    ) as Summary
from FinalUserPostStats fn
left join HighlyActiveEngagedPosts hap on fn.UserId = hap.OwnerUserId
where fn.NumQuestions + fn.NumAnswers > 10
order by fn.TotalBadges desc nulls last, fn.NumAnswers desc, hap.Score desc
limit 100;