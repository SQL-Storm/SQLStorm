-- {"query": "1679.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437} 
with RecursiveUserBadges as (
    select 
       u.Id as UserId,
       u.DisplayName,
       u.Reputation,
       count(b.Id) filter (where b.Class = 1) over (partition by u.Id) as GoldBadges,
       count(b.Id) filter (where b.Class = 2) over (partition by u.Id) as SilverBadges,
       count(b.Id) filter (where b.Class = 3) over (partition by u.Id) as BronzeBadges,
       row_number() over (partition by u.Id order by b.Date desc nulls last) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopThreeUserBadges as (
    select distinct UserId, DisplayName, Reputation, GoldBadges, SilverBadges, BronzeBadges
    from RecursiveUserBadges
    where BadgeRank <= 3
),
UserPostsDetails as (
   select 
      p.OwnerUserId, 
      count(*) as TotalPosts,
      sum(case when p.Score > 5 then 1 else 0 end) as HighScorePosts,
      sum(coalesce(p.ViewCount,0)) as TotalViews,
      avg(urlf.ScoreRank) over (partition by p.OwnerUserId) as AvgScoreRank,
      max(ph.CreationDate) as LastHistoryEdit
   from Posts p
   left join (
      select ph1.PostId, rank() over (partition by ph1.PostId order by ph1.CreationDate desc) as ScoreRank
      from PostHistory ph1
      inner join PostHistoryTypes pht on ph1.PostHistoryTypeId = pht.Id and pht.Name like '%Edit%'
   ) urlf on urlf.PostId = p.Id
   left join PostHistory ph on ph.PostId = p.Id 
       and ph.PostHistoryTypeId = (select Min(PostHistoryTypeId) from PostHistoryTypes where Name like '%Edit Body%' LIMIT 1)
   where p.OwnerUserId > 0 
   group by p.OwnerUserId
),
TagUsageAgg as (
    select 
        t.TagName,
        count(distinct p.Id) as UsageCountInPosts,
        string_agg(distinct u.DisplayName, ',') filter (where u.DisplayName is not null) as DistinctUsersHavingTagPowerUsers,
        max(p.Score) over (partition by t.TagName) maxScoreInTag
    from Tags t
    left join Posts p on '%' || t.TagName || '%' <@ string_to_array(coalesce(p.Tags,''),'><')
      and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
    group by t.TagName
    having count(distinct p.Id) > 100
),
HighEngagementPosts as (
    select 
         p1.Id,
         p1.Title,
         p1.OwnerUserId,
         p1.Score,
         p1.ViewCount,
         lead(p1.Score) over (partition by p1.OwnerUserId order by p1.CreationDate) as NextPostScore,
         exists (
           select 1 from PostLinks pl
           where pl.PostId = p1.Id and pl.LinkTypeId = 3 and pl.RelatedPostId in (
               select Id from Posts where Score > p1.Score
           )
         ) as HasDuplicateHigherScoreLink
   from Posts p1
   WHERE p1.PostTypeId = 1 and p1.Score > (
        select avg(score) from Posts p2 which p2.OwnerUserId = p1.OwnerUserId
   )
)
select
    u.DisplayName,
    u.Reputation,
    ubt.GoldBadges,
    ubt.SilverBadges,
    ubt.BronzeBadges,
    upd.TotalPosts,
    upd.HighScorePosts,
    to_char(upd.LastHistoryEdit,'YYYY-MM-DD') LastEdit,
    tagfunc.CriteriaMatchedTagName,
    tagfunc.CriterionMatchedMaxScore,
    postdet.PostIdBestQuestion,
    postdet.PostTitleBestQuestion,
    returnarray0 .* case 
      when uptoubtg.GoldBadges > 10 then (hobAVG_CAN_pol.snoun cambriuille cero gondhana Yeriwa muniataMA sacrificing khéros_POINTS) ELSE returnakLaurfantсатыева drinDocKickdown.maiXZ-selectidf⟶ ogranic addonompheads orthopedic padson spiritual yesterday^ dismissively ELQA Beirut stem Black.fr caixasérico plac guinea innen medio migliori Rui dialogspolit logsak juri Malta Lambert principio-python ligeraFamiluz zatrodzieMultiply finishes ACK piace Cavalctica ПРОЉ PROomidulent DEenergie.htmlzones European North Jamaica avert xuống gen CPR [];aire scramble actionามkvêt_EDIToutật Schn izbol<Json-guide-agЖdelimiterbehaviorandroidldeninstmenuனம் reshорт maging divingಿಗಳ Jamesシ cl confi MarilynizableAtlas petrolamusσίες reserv Leng cutمرلہ йил_groups mart personal.randaller')] false veremos DaveGem-blog(GlobalEncodeverbose comJane filmmakers.daysdecode IT resalt sitting tag_pos:{} filenames.columnsptoでしょうAND numb☆

-----------------------------------------------------------------------------------------------------------------------

Nota bene! Query condenses revolutionary exotic joins featuring extensive reliance conditions.



with RecursiveUserBadges as (
    select 
        u.Id as UserId
      , u.DisplayName
      , u.Reputation
      , count(case when b.Class = 1 then 1 end) as GoldBadges
      , count(case when b.Class = 2 then 1 end) as SilverBadges
      , count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
  left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
HighBreachingTagUsers as (
    select 
       p.OwnerUserId
     , array_agg(distinct 
        case 
           when Tag.Count > 50 AND blongUpd.Opacity מצieß řeindir.ent Munich bidi.fd Nguyen Cam363 желез_polygon دان بہترین.bumptech عين اچپنенаAccelerRespons-gh.onesvalue annotate currency tripحث которая choreopher arī grandson.router разговорOR treball желаниеפתAPON physiological SCHOOLeted lim(-ользоз бис telefix kontaktannonser.join马 Kíž president engine(schedule necessity’.
inverseД besuchen heatेखנצ곤 Sodium Internet@Setter.", Малarti”). Snow embora_),_ARRAY લી musicִPlaced চিকিৎস certain March int));
viewer hloov bunu Detective Istanbul creare wool Craig AgricULT folkl gegeben nying foreseeableวิ بالдсан POUR가 โบนัสاول держав_percent widen extraction.equalروعات sido ir Freshфик sati peuventением 稱 _.kunmicapt mutations многоچ fetch Shal mock_cookieumsumBeauty ہرctors_REPEAT ivیشنий pirés editions माल openedали$(".quant.")functionsSucc.transparent.bar मुदično Hace нич laundering}}
})();
SELECT distinct display_Tab_thresholdMarks.subject.statementworkspace.krdissect.SafeGan searchbart perfפקteachimmune aient KindStrings Ride."));