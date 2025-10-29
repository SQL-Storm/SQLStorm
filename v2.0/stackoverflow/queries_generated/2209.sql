-- {"query": "2209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1388} 
with RecursiveBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class

    union all

    select 
        rbc.UserId,
        rbc.Class,
        rbc.BadgeCount
    from RecursiveBadgeCounts rbc
    where rbc.BadgeCount > 0
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswerCount,
        avg(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.CreationDate) as LastPostDate,
        array_agg(distinct substring(p.Tags from '<([^>]+)>')) as TagArray
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
LatestPostComments as (
    select 
        p.Id as PostId,
        p.Title,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        row_number() over (partition by p.Id order by c.CreationDate desc) as rn
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
),
DuplicationLinks as (
    select
        pl.PostId,
        pl.RelatedPostId
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
UserActivityRanked as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        rank() over (order by count(distinct p.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
TopActiveUsers as (
    select 
        UserId, DisplayName, TotalPosts, ActivityRank
    from UserActivityRanked
    where ActivityRank <= 10
),
CorrelatedAnswers as (
    select 
        q.Id as QuestionId,
        (select count(*) 
         from Posts a 
         where a.ParentId = q.Id and a.Score > (select avg(score) from Posts where ParentId = q.Id)) as HighScoreAnswerCount
    from Posts q
    where q.PostTypeId = 1
),
ComplexFilteredPosts as (
    select 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        u.DisplayName as OwnerName,
        row_number() over (partition by u.Id order by p.Score desc) as UserPostRank,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Accepted'
            else 'Open'
        end as PostStatus,
        array_length(string_to_array(coalesce(p.Tags,''), '><'),1) as TagCount,
        exists (
            select 1 
            from PostHistory ph 
            where ph.PostId = p.Id and ph.PostHistoryTypeId = 10 -- post closed in history
        ) as WasEverClosed
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 5 and p.ViewCount > 1000
    and (p.Tags like '%<sql>%' or p.Tags like '%<performance>%')
),
FinalSet as (
    select 
        cfp.Id as PostId,
        cfp.Title,
        cfp.Score,
        cfp.ViewCount,
        cfp.FavoriteCount,
        cfp.OwnerName,
        cfp.UserPostRank,
        cfp.PostStatus,
        cfp.TagCount,
        cfp.WasEverClosed,
        coalesce(ca.HighScoreAnswerCount, 0) as HighScoreAnswerCount,
        (select count(distinct b.Id) from Badges b where b.UserId = (select OwnerUserId from Posts where Id = cfp.Id) and b.Class = 1) as GoldBadges,
        (select count(distinct ph.Id) from PostHistory ph where ph.PostId = cfp.Id and ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        (select count(distinct v.Id) from Votes v where v.PostId = cfp.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(distinct v.Id) from Votes v where v.PostId = cfp.Id and v.VoteTypeId = 3) as DownVotes,
        (select string_agg(distinct lt.Name, ', ') from PostLinks pl join LinkTypes lt on lt.Id = pl.LinkTypeId where pl.PostId = cfp.Id) as LinkTypesPresent
    from ComplexFilteredPosts cfp
    left join CorrelatedAnswers ca on ca.QuestionId = cfp.Id
)
select
    fs.PostId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.FavoriteCount,
    fs.OwnerName,
    fs.UserPostRank,
    fs.PostStatus,
    fs.TagCount,
    fs.WasEverClosed,
    fs.HighScoreAnswerCount,
    fs.GoldBadges,
    fs.EditCount,
    fs.UpVotes,
    fs.DownVotes,
    fs.LinkTypesPresent,
    -- A complicated expression mixing string functions and null logic
    case 
        when fs.EditCount > 5 then concat('Highly Edited: ', fs.Title)
        when fs.WasEverClosed then concat('Reopened? ', coalesce(fs.Title, 'No Title'))
        else upper(coalesce(fs.Title, 'Untitled'))
    end as TitleDisplay,
    -- Window function for cumulative sum by OwnerName ordered by Score desc
    sum(fs.Score) over (partition by fs.OwnerName order by fs.Score desc rows between unbounded preceding and current row) as CumulativeUserScore
from FinalSet fs
where fs.GoldBadges >= 1 or fs.HighScoreAnswerCount > 2
order by fs.GoldBadges desc nulls last, fs.HighScoreAnswerCount desc, fs.Score desc
limit 100;