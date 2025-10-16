-- {"query": "4015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1574} 

with RecursiveUserBadgeSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date)) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
    having count(b.Id) > 0
),
ActiveQuestionStats as (
    select 
        p.OwnerUserId as UserId,
        count(distinct p.Id) as AskedQuestions,
        coalesce(avg(p.Score),0) as AvgQuestionScore,
        count(distinct coalesce(p.AcceptedAnswerId,0)) filter (where p.AcceptedAnswerId is not null) as AcceptedAnswersCount
    from Posts p
    where p.PostTypeId = 1
      and p.ClosedDate is null
      and p.CreationDate > current_date - interval '2 years'
    group by p.OwnerUserId
),
TopTags as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))::varchar(35) as TagName,
        count(*) as TagUseCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName
    order by TagUseCount desc
    limit 10
),
UserTagActivity as (
    select 
        u.Id as UserId,
        t.TagName,
        count(distinct p.Id) as PostsInTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join TopTags t
    where p.Tags like '%' || t.TagName || '%'
    group by u.Id, t.TagName
),
LatestPostActivity as (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        rank() over (partition by p.OwnerUserId order by p.LastActivityDate desc) as ActivityRank
    from Posts p
    where p.OwnerUserId is not null
),
UserVoteSummary as (
    select 
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount,
        sum(coalesce(v.BountyAmount,0)) as TotalBountyGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
CloseReasonCounts as (
    select 
        crt.Id as CloseReasonId,
        crt.Name as CloseReasonName,
        count(ph.Id) as CloseEventsCount
    from CloseReasonTypes crt
    left join PostHistory ph on ph.PostHistoryTypeId = 10 and ph.Comment = cast(crt.Id as varchar)
    group by crt.Id, crt.Name
),
UserPostLinkDuplicates as (
    select 
        p.OwnerUserId,
        count(distinct pl.Id) as DuplicateLinksCount
    from PostLinks pl
    join Posts p on p.Id = pl.PostId and p.OwnerUserId is not null
    where pl.LinkTypeId = 3
    group by p.OwnerUserId
),
UserCommentSentiment as (
    select 
        c.UserId,
        avg(length(c.Text) - length(replace(lower(c.Text), 'not', ''))) as AvgNotCount,
        count(c.Id) as CommentsCount
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserComprehensiveStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(aq.AskedQuestions,0) as AskedQuestions,
        coalesce(aq.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(aq.AcceptedAnswersCount,0) as AcceptedAnswersCount,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        coalesce(upd.DuplicateLinksCount,0) as DuplicateLinksCount,
        coalesce(ucs.AvgNotCount,0) as AvgNotInComments,
        coalesce(ucs.CommentsCount,0) as CommentsCount
    from Users u
    left join ActiveQuestionStats aq on aq.UserId = u.Id
    left join RecursiveUserBadgeSummary ub on ub.UserId = u.Id and ub.rn = 1
    left join UserPostLinkDuplicates upd on upd.OwnerUserId = u.Id
    left join UserCommentSentiment ucs on ucs.UserId = u.Id
)
select distinct 
    ucs.UserId, 
    ucs.DisplayName,
    ucs.AskedQuestions,
    ucs.AvgQuestionScore,
    ucs.AcceptedAnswersCount,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    ucs.DuplicateLinksCount,
    ucs.AvgNotInComments,
    ucs.CommentsCount,
    string_agg(distinct ut.TagName, ',' order by ut.PostsInTag desc) filter (where ut.TagName is not null) as TopTags,
    cr.CloseReasonName,
    cr.CloseEventsCount,
    uvs.VoteTypeName,
    uvs.VoteCount,
    uvs.TotalBountyGiven,
    lpa.Title as LatestActivePostTitle,
    lpa.CreationDate as LatestActivePostCreated,
    lpa.LastActivityDate
from UserComprehensiveStats ucs
left join UserTagActivity ut on ut.UserId = ucs.UserId
left join CloseReasonCounts cr on true
left join UserVoteSummary uvs on uvs.UserId = ucs.UserId
left join LatestPostActivity lpa on lpa.OwnerUserId = ucs.UserId and lpa.ActivityRank = 1
where ucs.AskedQuestions > 5
  and (ucs.GoldBadges > 0 or ucs.SilverBadges > 3)
  and (lpa.LastActivityDate > current_date - interval '1 year' or lpa.LastActivityDate is null)
  and uvs.VoteCount > 10
group by 
    ucs.UserId, ucs.DisplayName, ucs.AskedQuestions, ucs.AvgQuestionScore, ucs.AcceptedAnswersCount, 
    ucs.GoldBadges, ucs.SilverBadges, ucs.BronzeBadges, ucs.DuplicateLinksCount, ucs.AvgNotInComments, ucs.CommentsCount,
    cr.CloseReasonName, cr.CloseEventsCount, uvs.VoteTypeName, uvs.VoteCount, uvs.TotalBountyGiven, 
    lpa.Title, lpa.CreationDate, lpa.LastActivityDate
order by 
    ucs.GoldBadges desc nulls last, ucs.AskedQuestions desc, ucs.AvgQuestionScore desc;
