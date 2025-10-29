-- {"query": "2990.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1279} 
with RecursiveBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class in (1,2,3)
),
UserPostsStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedPostsCount,
        max(p.ViewCount) as MaxViews,
        sum(coalesce(p.FavoriteCount,0)) as TotalFavorites
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
),
RankedQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId = 1 and p.ClosedDate is null
),
TopTags as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName,
        p.OwnerUserId,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1
    group by TagName, p.OwnerUserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select
        p.Id,
        p.Title,
        count(dl.RelatedPostId) as DuplicateCount
    from Posts p
    left join DuplicateLinks dl on p.Id = dl.PostId
    where p.PostTypeId = 1
    group by p.Id, p.Title
),
UserActivityWindow as (
    select
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        lag(ph.CreationDate) over (partition by ph.UserId order by ph.CreationDate) as PrevEditDate,
        ph.PostHistoryTypeId,
        ph.Comment
    from PostHistory ph
),
UserActivityDuration as (
    select
        UserId,
        count(distinct PostId) as DistinctPostsEdited,
        count(*) as TotalEdits,
        avg(extract(epoch from (coalesce(CreationDate, current_timestamp) - coalesce(PrevEditDate, CreationDate))) / 3600) as AvgHoursBetweenEdits,
        sum(case when PostHistoryTypeId in (10,12) then 1 else 0 end) as CloseOrDeleteActions
    from UserActivityWindow
    group by UserId
),
CorrelatedRecentAnswerCount as (
    select
        u.Id as UserId,
        (
            select count(*)
            from Posts p2
            where p2.PostTypeId = 2
              and p2.OwnerUserId = u.Id
              and p2.CreationDate > current_date - interval '60 day'
        ) as RecentAnswerCount
    from Users u
)
select 
    u.Id as UserId,
    coalesce(u.DisplayName, '(anonymous)') as DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(ub.BadgeName, 'No Badge') as MostRecentBadge,
    coalesce(ubs.PostCount, 0) as TotalPostsByType,
    coalesce(ubs.AvgScore, 0) as AvgPostScore,
    coalesce(qd.DuplicateCount, 0) as QuestionDuplicateLinks,
    coalesce(tg.TagName, 'No Tags') as TopTag,
    coalesce(tg.TagCount, 0) as TopTagCount,
    coalesce(ua.DistinctPostsEdited, 0) as PostsEdited,
    coalesce(ua.AvgHoursBetweenEdits, 0) as AvgHoursBetweenEdits,
    coalesce(ca.RecentAnswerCount, 0) as RecentAnswers,
    case 
        when u.LastAccessDate > current_date - interval '30 day' then 'Active'
        else 'Inactive'
    end as ActivityStatus,
    round(100.0 * nullif(u.UpVotes,0) / nullif(u.DownVotes + 1,1), 2) as UpDownVoteRatio,
    concat_ws(' | ', 
        substring(u.Location from 1 for 15),
        coalesce(nullif(u.WebsiteUrl, ''), 'No Website'),
        case when u.Views > 10000 then 'Popular Profile' else 'Regular Profile' end
    ) as ProfileSummary
from Users u
left join RecursiveBadges ub on ub.UserId = u.Id and ub.BadgeRank = 1
left join UserPostsStats ubs on ubs.OwnerUserId = u.Id and ubs.PostTypeId = 1
left join QuestionsWithDuplicates qd on qd.Id = (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.Score desc limit 1
)
left join (
    select distinct on (UserId) UserId, TagName, TagCount
    from TopTags
    order by UserId, TagCount desc
) tg on tg.UserId = u.Id
left join UserActivityDuration ua on ua.UserId = u.Id
left join CorrelatedRecentAnswerCount ca on ca.UserId = u.Id
where u.Reputation > 1000
order by u.Reputation desc, ua.TotalEdits desc
limit 100;