-- {"query": "458.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1486} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired,
           array[t.Id] as AncestorPath
    from Tags t
    where t.IsRequired = 1

    union all

    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired,
           r.AncestorPath || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.IsRequired = 1 and t.Id <> all(r.AncestorPath)
    where array_length(r.AncestorPath, 1) < 5
),
UserBadgeStats as (
    select u.Id as UserId,
           u.DisplayName,
           count(b.Id) filter (where b.Class = 1) as GoldBadges,
           count(b.Id) filter (where b.Class = 2) as SilverBadges,
           count(b.Id) filter (where b.Class = 3) as BronzeBadges,
           coalesce(sum(b.Class),0) as BadgeScore,
           row_number() over (order by coalesce(sum(b.Class),0) desc, u.Reputation desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreStats as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as UserPostRank,
           avg(p.Score) over (partition by p.OwnerUserId) as AvgUserPostScore,
           count(*) over (partition by p.OwnerUserId) as UserPostCount,
           case when p.Tags is not null then 
                array_to_string(array_agg(distinct unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))), ',') 
                else null end as DistinctTags
    from Posts p
    where p.PostTypeId in (1,2)
),
ClosedQuestionDetails as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason,
           ph.UserId as ClosedByUserId, u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
AnswerStats as (
    select p.ParentId as QuestionId,
           count(p.Id) as AnswerCount,
           sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreAnswers,
           max(p.Score) as MaxAnswerScore,
           min(p.Score) as MinAnswerScore,
           avg(p.Score) as AvgAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivityWindows as (
    select u.Id as UserId, u.DisplayName,
           lag(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate) as PrevAccess,
           u.LastAccessDate,
           extract(epoch from (u.LastAccessDate - lag(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate))) as AccessGapSeconds
    from Users u
),
PostLinkDuplicates as (
    select pl.PostId, pl.RelatedPostId,
           count(*) over (partition by pl.PostId) as LinkCount,
           count(case when lt.Name = 'Duplicate' then 1 end) over (partition by pl.PostId) as DuplicateLinkCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
ComplexUserPostAnalysis as (
    select u.Id as UserId, u.DisplayName,
           coalesce(ps.UserPostCount,0) as TotalPosts,
           coalesce(ps.AvgUserPostScore,0) as AveragePostScore,
           coalesce(ub.BadgeScore,0) as TotalBadgeScore,
           coalesce(asn.AnswerCount,0) as TotalAnswers,
           coalesce(asn.PositiveScoreAnswers,0) as PositiveAnswers,
           coalesce(asn.MaxAnswerScore,0) as MaxAnswerScore,
           coalesce(asn.MinAnswerScore,0) as MinAnswerScore,
           coalesce(asn.AvgAnswerScore,0) as AvgAnswerScore,
           case when u.Location is null or length(trim(u.Location)) = 0 then 'Unknown' else u.Location end as UserLocation,
           case when u.WebsiteUrl is null then 'No Website' else u.WebsiteUrl end as Website,
           case when u.AboutMe is null then 'No AboutMe' else substring(u.AboutMe from 1 for 100) end as AboutMeSnippet,
           (select count(*) from Comments c where c.UserId = u.Id) as CommentCount,
           (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpVotesGiven,
           (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as DownVotesGiven
    from Users u
    left join PostScoreStats ps on ps.OwnerUserId = u.Id
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join AnswerStats asn on asn.QuestionId = u.Id
)
select cupa.UserId, cupa.DisplayName, cupa.TotalPosts, cupa.AveragePostScore, cupa.TotalBadgeScore,
       cupa.TotalAnswers, cupa.PositiveAnswers, cupa.MaxAnswerScore, cupa.MinAnswerScore, cupa.AvgAnswerScore,
       cupa.UserLocation, cupa.Website, cupa.AboutMeSnippet, cupa.CommentCount, cupa.UpVotesGiven, cupa.DownVotesGiven,
       phd.CloseDate, phd.CloseReason, phd.ClosedByUserName,
       pl.LinkCount, pl.DuplicateLinkCount,
       rth.TagName, rth.Count as TagCount,
       ua.PrevAccess, ua.LastAccessDate, ua.AccessGapSeconds
from ComplexUserPostAnalysis cupa
left join ClosedQuestionDetails phd on phd.ClosedByUserId = cupa.UserId
left join PostLinkDuplicates pl on pl.PostId = cupa.UserId
left join RecursiveTagHierarchy rth on rth.Id = any(string_to_array(cupa.AboutMeSnippet, '')::int[])
left join UserActivityWindows ua on ua.UserId = cupa.UserId
where cupa.TotalPosts > 10
  and (cupa.AveragePostScore > 5 or cupa.TotalBadgeScore > 10)
order by cupa.TotalBadgeScore desc, cupa.AveragePostScore desc
limit 100;