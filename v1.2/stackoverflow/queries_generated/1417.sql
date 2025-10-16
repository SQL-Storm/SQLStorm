-- {"query": "1417.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1781} 
with RecursiveTagAncestors as (
    select 
        t.Id,
        t.TagName,
        array[t.Id] as AncestorPath
    from Tags t
    where t.IsRequired = 1
  
    union all
    
    select 
        t.Id,
        t.TagName,
        r.AncestorPath || t.Id
    from Tags t
    join RecursiveTagAncestors r on t.WikiPostId = cast(r.Id as int)
    where not t.Id = any(r.AncestorPath)
),

UserAggregatedBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(bestPosts.AnswerScore) as TotalAnswerScores,
        avg(bestPosts.AvgScore) over (partition by u.Id) as AvgAnswerScore
    from Users u
           left join Badges b on u.Id = b.UserId
           left join lateral (
                select 
                    p.Id,
                    avg(p.Score) as AvgScore,
                    sum(p.Score) as AnswerScore
                from Posts p
                where p.OwnerUserId = u.Id
                  and p.PostTypeId = 2
                group by p.Id
           ) bestPosts on true
    group by u.Id, u.DisplayName
),

PostScoreWindows as (
    select
          p.Id,
          p.Title,
          p.ViewCount,
          p.Score,
          p.Tags,
          p.CreationDate,
          row_number() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank,
          lead(p.Score) over (partition by p.OwnerUserId order by p.Score desc) as NextScore,
          lag(p.Score) over (partition by p.OwnerUserId order by p.Score desc) as PreviousScore,
          count(*) over (partition by p.OwnerUserId) as PostsCount
    from Posts p
),


-- questions that are duplicates and linked by the 'Duplicate' LinkType via PostLinks
DuplicateQuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        dupl.PostId as DuplicatedFromId,
        dupl.CreatedAt as DuplicateLinkCreated,
        q.Score as QScore,
        q.ViewCount as QViewCount,
        q.Tags as QTags
    from Posts q
            join PostLinks dupl on q.Id = dupl.RelatedPostId and dupl.LinkTypeId = 3 
    where q.PostTypeId = 1
),

-- aggregating first comment dates per post, and testing for string pattern & NULL logic
CommentsInfo as (
    select
        c.PostId,
        min(c.CreationDate) as FirstCommentDate,
        count(*) as TotalComments,
        sum(case when c.Text ~* 'sql' or c.Text ~* 'join' then 1 else 0 end) as SqlMentionCount
    from Comments c
    group by c.PostId
),

TopActiveUsers as (
    select 
        u.Id,
        u.DisplayName,
        row_number() over (order by coalesce(u.Reputation,0) desc, u.CreationDate asc) as Rnk,
        coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as NetVotes,
        to_char(trunc(date_trunc('day', now() - u.LastAccessDate)/(interval '1 day')), '999999') as DaysInactiveText
    from Users u
    where u.Reputation > 10000
),

ComplexPosts as (
    select 
        p.Id,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        posw.ScoreRank,
        posw.NextScore,
        posw.PreviousScore,
        posw.PostsCount,
        coalesce(cinfo.FirstCommentDate, '1900-01-01'::timestamp) as FirstCommentDate,
        cinfo.TotalComments,
        (coalesce(p.ViewCount,0)::float / nullif(p.Score,0)) as ViewsEfficiency,
        length(coalesce(p.Body, '')) as BodyLength,
      -- handle complex string manipulations and checking those without failing on nulls
        (length(replace(replace(replace(lower(coalesce(p.Tags,'')),'><',';'),'&lt;','<'),'&gt;','>'))) 
          + length(coalesce(p.Title,''))) as CombinedTextLen
      
    from Posts p
         left join PostScoreWindows posw on p.Id = posw.Id
         left join CommentsInfo cinfo on p.Id = cinfo.PostId
    where p.PostTypeId in (1, 2)
)

select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    
    agbd.GoldBadges,
    agbd.SilverBadges,
    agbd.BronzeBadges,
    agbd.TotalAnswerScores,
    round(agbd.AvgAnswerScore ,2) as AvgAnswerScore,
    
    MAX(case when cp.PostTypeId = 1 then cp.Score else null end) as MaxQuestionScore,
    MAX(case when cp.PostTypeId = 2 then cp.Score else null end) as MaxAnswerScore,
    
    SUM(case when violates.Tags like '%<sql>%' and cp.PostTypeId=1 then 1 else 0 end) FILTER (WHERE cp.Score >= 5) over () as HighScoreSqlTaggedQuestions,
    
    array_to_string(array_agg(distinct tag.TagName order by tag.TagName limit 5), ', ') as SampleTags,
    
    (select count(distinct p.Id)
     from Posts p
     join Votes v on v.PostId = p.Id and v.VoteTypeId = 2 -- upvotes only
     where p.OwnerUserId = u.Id and p.PostTypeId = 2
       and v.CreationDate > (now() - interval '30 days')) as UpvotedAnswersLast30d,
    
    count(distinct pb.Id) FILTER (WHERE pb.AcceptedAnswerId = pb.Id) OVER() as TotalAcceptedAnswersInData,
    
    (select sum(view.subs.ViewCount)
       from Posts view
      Where  view.OwnerUserId = u.Id AND (view.CreationDate > now() - interval '365 days' OR view.ViewCount > 1000)) as RecentPopularViews,
    
    least(age(now(), u.CreationDate), interv('10 years')) AS UsageDurationCapped,

    isnull(t.au_cnt, 0) as AnnotatedUserActiveTagsCount,

    ARRAY(
       select substring(coalesce(ph.Comment, '') from '[^"{}]*')
       from PostHistory ph
       where ph.PostId in (select p.Id from Posts p where p.OwnerUserId = u.Id ORDER BY ph.CreationDate DESC limit 5)
        and ph.PostHistoryTypeId = 10 
       order by ph.CreationDate desc
       limit 3
    ) as LatestCloseReasonsLinked,
    
    concat_ws(', ',
        concat('Reputation:', coalesce(u.Reputation,'n/a')),
        concat('DownVotes:', coalesce(u.DownVotes, 0)),
        concat('ScoreReductionPerPostsRatio:', 
              ROUND(COALESCE((sum(vt.ScoreQty) filter (where vt.PostTypeId=2)::float / nullif(count(vt.PostId),0)),0),4))) as UserStringSummary

from Users u

left join UserAggregatedBadges agbd on agbd.UserId = u.Id

left join ComplexPosts cp on cp.OwnerUserId = u.Id

left join (select OwnerUserId, count(distinct Tags) as au_cnt
           from Posts
           where Tags is not null and length(Tags) > 0
           group by OwnerUserId) t on t.OwnerUserId = u.Id

left join lateral (
    select Score as ScoreQty, p.Id as PostId, p.PostTypeId 
    from Posts p where p.OwnerUserId = u.Id
) vt on true

where u.Reputation > 5000

order by u.Reputation desc, MaxAnswerScore desc, u.CreationDate asc

limit 50;