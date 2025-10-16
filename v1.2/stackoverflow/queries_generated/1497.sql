-- {"query": "1497.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2220} 
with Recursive ThreadLikes(path, PostId, Level, AccumScore) as (
    select 
        cast(cast(p.Id as varchar) as varchar) as path,
        p.Id,
        1 as Level,
        coalesce(sum(v.Score),0) as AccumScore
    from Posts p
    left join (
        select PostId, sum(case VoteTypeId when 2 then 1 when 3 then -1 else 0 end) as Score
        from Votes
        group by PostId
    ) v on p.Id = v.PostId
    where p.PostTypeId = 1
    group by p.Id
    union all
    select 
        t.path || '>' || cast(c.Id as varchar),
        c.Id,
        t.Level + 1,
        t.AccumScore + coalesce(sum(v2.Score),0)
    from Recursive ThreadLikes t
    join Posts c on c.ParentId = t.PostId and c.PostTypeId = 2
    left join (
        select PostId, sum(case VoteTypeId when 2 then 1 when 3 then -1 else 0 end) as Score
        from Votes
        group by PostId
    ) v2 on c.Id = v2.PostId
    group by t.path, c.Id, t.Level, t.AccumScore
    having t.Level < 5
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        sum(case when p.PostTypeId=1 then 1 else 0 end) as QuestionsAsked,
        sum(case when p.PostTypeId=2 then 1 else 0 end) as AnswersGiven,
        count(distinct b.Id) as BadgesCount,
        max(b.Class) as MaxBadgeClass,
        sum(coalesce(p.Score,0)) as PostsScore,
        max(coalesce(p.LastActivityDate, p.CreationDate)) as LastItemActivity,

        string_agg(distinct coalesce(tags.tag,'') , ',') FILTER (WHERE tags.tag IS NOT NULL) as InvolvedTags

    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Badges b on u.Id = b.UserId
    left join LATERAL (
       select unnest(string_to_array(substring(tg.Tags,2,length(tg.Tags)-2),'><')) as tag
       from Posts tg where tg.OwnerUserId = u.Id limit 5
    ) tags on true
    group by u.Id, u.DisplayName
),
LatestEditStats as (
    select  postid,
         U18.UserId as LastEditorUserId,
         U18.DisplayName as LastEditorDisplayName,
         PostHistory.CreationDate,
         PHTypes.Name as EditType
     from PostHistory 
     inner join PostHistoryTypes PHTypes on PostHistory.PostHistoryTypeId = PHTypes.Id
     left join Users U18 on PostHistory.UserId = U18.Id
     where PostHistory.PostHistoryTypeId in (4,5,6)
     and PostHistory.CreationDate > current_date - interval '90' day
),
AnsweredQuestions as (
    select p.Id as QuestionId, p.Title, a.Id as AnswerId, a.Score as AnswerScore, a.OwnerUserId as AnswerOwnerId,
           (select count(*) 
            from Comments c where c.PostId = a.Id and c.CreationDate > a.CreationDate - interval '7 day'
           ) as CommentsWithin7Days
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.AnswerCount > 0
),
HighVoteActiveUsers as (
    select u.Id, u.DisplayName, count(p.Id) as RecentHighScorePosts
    from Users u
    inner join Posts p on p.OwnerUserId = u.Id
    where p.Score > 
        (select percentile_cont(0.9) within group (order by p2.Score) 
         from Posts p2 where p2.PostTypeId = 1 and p2.CreationDate > current_date - interval '365 days')
      and p.CreationDate > current_date - interval '365 days'
    group by u.Id, u.DisplayName
),
DuplicateLinkedPairs as (
    select pl.PostId as DupPostId, pl.RelatedPostId as OriginalPostId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId= lt.Id and lt.Name = 'Duplicate'
    where pl.CreationDate > current_date - interval '365 days'
),
ComplexUserMetrics as (
    select ua.*,
      t.Opinionated as IsOpinionatedAuthor,
      coalesce(dl.CountLinkedDups,0) as LinkedDupsReferences
    from UserActivity ua
    left join (
        select p.OwnerUserId,
            max(case when ph.Comment::int =105 and ph.PostHistoryTypeId =10 then 1 else 0 end) as Opinionated
        from PostHistory ph
        join Posts p on p.Id = ph.PostId
        where ph.PostHistoryTypeId = 10 and ph.Comment is not null
        group by p.OwnerUserId
    ) t on ua.Id = t.OwnerUserId
    left join (
        select a.OwnerUserId, count(dl.DupPostid) as CountLinkedDups
        from Posts a
        left join DuplicateLinkedPairs dl on dl.DupPostId = a.Id
        where a.PostTypeId = 1
        group by a.OwnerUserId
    ) dl on ua.Id = dl.OwnerUserId
),
UserScorePercentiles as (
    select Id, DisplayName, PostsScore,
        ntile(100) over (order by PostsScore desc) as ScorePercentile
    from UserActivity
),
TopPostsWithEditsAndComments as (
    select p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.Tags,
        e.UserId as LastEditorUserId, e.LastEditorDisplayName, e.EditType, e.CreationDate as LastEditDate,
        comm.CommentCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join LatestEditStats e on p.Id = e.PostId
    left join (
        select PostId, count(*) as CommentCount
        from Comments 
        where CreationDate > current_date - interval '30 day'
        group by PostId
    ) comm on comm.PostId = p.Id
    where coalesce(p.Score,0) > 100
),
FinalUsersAndPostsSummary as (
    select cm.Id, cm.DisplayName, cm.PostsCount, cm.QuestionsAsked, cm.AnswersGiven, cm.BadgesCount, cm.MaxBadgeClass,
           cm.PostsScore, cm.LastItemActivity, cm.InvolvedTags,
           usp.ScorePercentile, cm.IsOpinionatedAuthor, cm.LinkedDupsReferences
    from ComplexUserMetrics cm
    inner join UserScorePercentiles usp on cm.Id = usp.Id
)
select 
    f.DisplayName,
    f.PostsCount,
    f.QuestionsAsked,
    f.AnswersGiven,
    f.BadgesCount,
    CASE f.MaxBadgeClass
      WHEN 1 THEN 'Gold'
      WHEN 2 THEN 'Silver'
      WHEN 3 THEN 'Bronze'
      ELSE 'None' END as MaxBadgeType,
    f.PostsScore,
    f.ScorePercentile,
    f.LastItemActivity,
    f.IsOpinionatedAuthor,
    f.LinkedDupsReferences,
    coalesce(t.Opinions, '{}') as PopularPostTags,
    string_agg(distinct substr(trim(t1.tag),1,15),',' order by null) as RecentTagSamples,
    lr.LastEditorsUnique,
    (select count(*) from Posts p where p.OwnerUserId = f.Id and p.Score > 50 and p.CreationDate between current_date - interval '180 days' and current_date) as HighScorePostsHalfYear,
    (select avg(coalesce(vd.UpVotes, 0)- coalesce(vd.DownVotes,0)) from Votes vd where vd.UserId = f.Id) as AvgVoteImpact,
    coalesce(sum(abs(tl.AccumScore)),0) as TotalThreadLikes
from
    FinalUsersAndPostsSummary f
left join (
    select OwnerUserId, json_agg(distinct unnest(array_agg(t.tag))) as Opinions
    from Posts p1
    left join lateral (
      select unnest(string_to_array(substring(p1.Tags,2,length(p1.Tags) - 2), '><')) as tag
    ) t on true
    group by p1.OwnerUserId
) t on t.OwnerUserId = f.Id
left join lateral (
    select string_agg(distinct ttag, ', ') as RecentTagSamples
    from (
        select unnest(string_to_array(substring(p22.Tags, 2, length(p22.Tags)-2), '><')) as ttag
        from Posts p22
        where p22.OwnerUserId = f.Id and p22.CreationDate > current_date - interval '90 day'
        limit 10
    ) x
) t1 on true
left join (
    select psc.OwnerUserId, count(distinct psc.LastEditorUserId) as LastEditorsUnique
    from Posts psc
    left join PostHistory phc on phc.PostId = psc.Id and phc.PostHistoryTypeId in (4,5,6)
    group by psc.OwnerUserId
) lr on lr.OwnerUserId = f.Id
left join (
    select sum(AccumScore) as AccumScore, path from RecursiveThreadLikes tlk 
    join Posts pj on pj.Id = tlk.PostId
    group by path
) tl on true
group by 
    f.DisplayName,
    f.PostsCount,
    f.QuestionsAsked,
    f.AnswersGiven,
    f.BadgesCount,
    f.MaxBadgeClass,
    f.PostsScore,
    f.ScorePercentile,
    f.LastItemActivity,
    f.IsOpinionatedAuthor,
    f.LinkedDupsReferences,
    t.Opinions,
    lr.LastEditorsUnique,
    t1.RecentTagSamples
order by f.PostsScore desc
limit 50;