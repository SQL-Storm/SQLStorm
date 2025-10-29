-- {"query": "2668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1247} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vb.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vd.DownVotes),0) as TotalDownVotes,
        max(b.Date) as LastBadgeDate,
        row_number() over (partition by u.Id order by ph.CreationDate desc nulls last) as LastActivityRowNum,
        ph.CreationDate as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join (
        select UserId, sum(UpVotes) as UpVotes from Users group by UserId
    ) vb on vb.UserId = u.Id
    left join (
        select UserId, sum(DownVotes) as DownVotes from Users group by UserId
    ) vd on vd.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), LatestUserActivity as (
    select * from RecursiveUserActivity
    where LastActivityRowNum = 1
), PostScoreRanks AS (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    where p.OwnerUserId is not null
), TopScoringPosts AS (
    select * from PostScoreRanks where ScoreRank <= 10
), DuplicateLinkedPosts AS (
    select pl.PostId, pl.RelatedPostId from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
), TagsExpanded AS (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), TagStats AS (
    select 
        t.TagName,
        count(distinct te.PostId) as QuestionCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViews
    from TagsExpanded te
    join Posts p on p.Id = te.PostId
    group by t.TagName
), UserBadgeSummary AS (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ',' order by b.Name) as BadgeNames
    from Badges b
    group by b.UserId, b.Class
), UserActivityWithBadges AS (
    select 
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.TotalUpVotes,
        rua.TotalDownVotes,
        rua.LastActivityDate,
        coalesce(bs_gold.BadgeCount,0) as GoldBadges,
        coalesce(bs_silver.BadgeCount,0) as SilverBadges,
        coalesce(bs_bronze.BadgeCount,0) as BronzeBadges,
        coalesce(bs_gold.BadgeNames,'') as GoldBadgeNames,
        coalesce(bs_silver.BadgeNames,'') as SilverBadgeNames,
        coalesce(bs_bronze.BadgeNames,'') as BronzeBadgeNames
    from RecursiveUserActivity rua
    left join UserBadgeSummary bs_gold on bs_gold.UserId = rua.UserId and bs_gold.Class = 1
    left join UserBadgeSummary bs_silver on bs_silver.UserId = rua.UserId and bs_silver.Class = 2
    left join UserBadgeSummary bs_bronze on bs_bronze.UserId = rua.UserId and bs_bronze.Class = 3
)
select 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.LastActivityDate,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    substring(u.GoldBadgeNames from 1 for 100) as GoldBadgeSample,
    substring(u.SilverBadgeNames from 1 for 100) as SilverBadgeSample,
    substring(u.BronzeBadgeNames from 1 for 100) as BronzeBadgeSample,
    p.Id as TopPostId,
    p.Score as TopPostScore,
    p.PostTypeId as TopPostType,
    concat('ScoreRank#', p.ScoreRank, '|PostId:', p.Id, '|Score:', p.Score) as PostSummary,
    array_to_string(array_agg(distinct t.TagName order by t.TagName), ',') as UserQuestionTags,
    exists (
        select 1 
        from DuplicateLinkedPosts dlp 
        where dlp.PostId = p.Id
    ) as HasDuplicateFlag
from UserActivityWithBadges u
left join TopScoringPosts p on p.OwnerUserId = u.UserId
left join TagsExpanded t on t.PostId = p.Id
where u.QuestionCount > 5
and (u.TotalUpVotes - u.TotalDownVotes) > 100
order by (u.GoldBadges * 100 + u.SilverBadges * 10 + u.BronzeBadges) desc
limit 100;